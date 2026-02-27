#!/usr/bin/env bash
# Gitleaks scanner wrapper — secret detection
# Usage: gitleaks.sh [--scope-file <file>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SCOPE_FILE=""
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope-file) SCOPE_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/gitleaks-findings.jsonl"
> "$FINDINGS_FILE"

log_step "Running Gitleaks (secret detection)..."

RAW_OUTPUT=$(mktemp /tmp/cg-gitleaks-XXXXXX.json)
EXIT_CODE=0

GITLEAKS_ARGS=("detect" "--source" "." "--report-format" "json" "--report-path" "$RAW_OUTPUT" "--no-banner")

DOCKER_IMAGE="zricethezav/gitleaks:latest"

CONTAINER_SVC=$(get_container_service_for_tool "gitleaks" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" gitleaks "${GITLEAKS_ARGS[@]}" \
    2>/dev/null || EXIT_CODE=$?
elif docker_available; then
  docker run --rm -v "$(pwd):/workspace" -w /workspace \
    "$DOCKER_IMAGE" detect --source /workspace \
    --report-format json --report-path /workspace/.gitleaks-report.json \
    --no-banner 2>/dev/null || EXIT_CODE=$?
  [[ -f .gitleaks-report.json ]] && mv .gitleaks-report.json "$RAW_OUTPUT"
elif cmd_exists gitleaks; then
  gitleaks "${GITLEAKS_ARGS[@]}" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "Gitleaks not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Parse output
if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    if isinstance(data, list):
        for leak in data:
            finding = {
                'tool': 'gitleaks',
                'severity': 'high',
                'rule': leak.get('RuleID', leak.get('ruleID', '')),
                'message': f\"Secret detected: {leak.get('Description', leak.get('description', ''))}\",
                'file': leak.get('File', leak.get('file', '')),
                'line': leak.get('StartLine', leak.get('startLine', 0)),
                'autoFixable': False,
                'category': 'secrets'
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
  log_warn "Gitleaks: found $count secret(s)!"
else
  log_ok "Gitleaks: no secrets found"
fi

echo "$FINDINGS_FILE"
