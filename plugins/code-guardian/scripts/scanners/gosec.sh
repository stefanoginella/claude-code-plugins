#!/usr/bin/env bash
# gosec scanner wrapper — Go SAST
# Usage: gosec.sh [--scope-file <file>]
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

FINDINGS_FILE="${OUTPUT_DIR}/gosec-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f go.mod ]]; then
  log_info "No go.mod found, skipping gosec"
  exit 0
fi

log_step "Running gosec (Go SAST)..."

RAW_OUTPUT=$(mktemp /tmp/cg-gosec-XXXXXX.json)
EXIT_CODE=0

DOCKER_IMAGE="securego/gosec:latest"

CONTAINER_SVC=$(get_container_service_for_tool "gosec" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" gosec -fmt=json -out=/tmp/gosec-output.json ./... 2>/dev/null || EXIT_CODE=$?
  $(get_compose_cmd) cp "$CONTAINER_SVC":/tmp/gosec-output.json "$RAW_OUTPUT" 2>/dev/null || true
elif docker_available; then
  docker run --rm -v "$(pwd):/workspace" -w /workspace \
    "$DOCKER_IMAGE" -fmt=json -out=/workspace/.gosec-output.json ./... 2>/dev/null || EXIT_CODE=$?
  [[ -f .gosec-output.json ]] && mv .gosec-output.json "$RAW_OUTPUT"
elif cmd_exists gosec; then
  gosec -fmt=json -out="$RAW_OUTPUT" ./... 2>/dev/null || EXIT_CODE=$?
else
  log_warn "gosec not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for issue in data.get('Issues', []):
        sev = issue.get('severity', 'MEDIUM').lower()
        finding = {
            'tool': 'gosec',
            'severity': sev if sev in ('high','medium','low') else 'medium',
            'rule': issue.get('rule_id', issue.get('cwe', {}).get('id', '')),
            'message': issue.get('details', ''),
            'file': issue.get('file', ''),
            'line': int(issue.get('line', '0').split('-')[0]) if issue.get('line') else 0,
            'autoFixable': False,
            'category': 'sast'
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
  log_warn "gosec: found $count issue(s)"
else
  log_ok "gosec: no issues found"
fi

echo "$FINDINGS_FILE"
