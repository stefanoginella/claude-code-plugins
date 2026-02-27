#!/usr/bin/env bash
# Trivy scanner wrapper — vulnerability scanning (filesystem, containers, IaC)
# Usage: trivy.sh [--mode fs|image|config] [--target <path_or_image>] [--scope-file <file>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

MODE="fs"
TARGET="."
SCOPE_FILE=""
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --scope-file) SCOPE_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/trivy-findings.jsonl"
> "$FINDINGS_FILE"

log_step "Running Trivy ($MODE mode)..."

RAW_OUTPUT=$(mktemp /tmp/cg-trivy-XXXXXX.json)
EXIT_CODE=0

TRIVY_ARGS=("$MODE" "--format" "json" "--quiet")

case "$MODE" in
  fs)
    TRIVY_ARGS+=("--scanners" "vuln,secret,misconfig")
    TRIVY_ARGS+=("$TARGET")
    ;;
  image)
    TRIVY_ARGS+=("$TARGET")
    ;;
  config)
    TRIVY_ARGS+=("$TARGET")
    ;;
esac

DOCKER_IMAGE="aquasec/trivy:latest"

CONTAINER_SVC=$(get_container_service_for_tool "trivy" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" trivy "${TRIVY_ARGS[@]}" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif docker_available; then
  local_args=("${TRIVY_ARGS[@]}")
  docker_run_args=("--rm" "-v" "$(pwd):/workspace" "-w" "/workspace")
  # For image scanning, need Docker socket
  [[ "$MODE" == "image" ]] && docker_run_args+=("-v" "/var/run/docker.sock:/var/run/docker.sock")
  # Trivy cache
  docker_run_args+=("-v" "${HOME}/.cache/trivy:/root/.cache/")

  docker run "${docker_run_args[@]}" "$DOCKER_IMAGE" "${local_args[@]}" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists trivy; then
  trivy "${TRIVY_ARGS[@]}" > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "Trivy not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Parse trivy JSON output
if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    results = data.get('Results', [])
    for result in results:
        target = result.get('Target', '')
        # Vulnerabilities
        for vuln in result.get('Vulnerabilities', []):
            sev = vuln.get('Severity', 'UNKNOWN').lower()
            if sev == 'critical': sev = 'high'
            finding = {
                'tool': 'trivy',
                'severity': sev if sev in ('high','medium','low','info') else 'info',
                'rule': vuln.get('VulnerabilityID', ''),
                'message': f\"{vuln.get('PkgName','')}: {vuln.get('Title','')}\",
                'file': target,
                'line': 0,
                'autoFixable': vuln.get('FixedVersion', '') != '',
                'category': 'dependency'
            }
            print(json.dumps(finding))
        # Secrets
        for secret in result.get('Secrets', []):
            finding = {
                'tool': 'trivy',
                'severity': secret.get('Severity', 'high').lower(),
                'rule': secret.get('RuleID', ''),
                'message': secret.get('Title', ''),
                'file': target,
                'line': secret.get('StartLine', 0),
                'autoFixable': False,
                'category': 'secrets'
            }
            print(json.dumps(finding))
        # Misconfigs
        for mc in result.get('Misconfigurations', []):
            sev = mc.get('Severity', 'UNKNOWN').lower()
            if sev == 'critical': sev = 'high'
            finding = {
                'tool': 'trivy',
                'severity': sev if sev in ('high','medium','low','info') else 'info',
                'rule': mc.get('ID', ''),
                'message': mc.get('Title', ''),
                'file': target,
                'line': 0,
                'autoFixable': False,
                'category': 'iac'
            }
            print(json.dumps(finding))
except Exception as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
" > "$FINDINGS_FILE"
  fi
fi

rm -f "$RAW_OUTPUT"

count=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$count" -gt 0 ]]; then
  log_warn "Trivy ($MODE): found $count issue(s)"
else
  log_ok "Trivy ($MODE): no issues found"
fi

echo "$FINDINGS_FILE"
