#!/usr/bin/env bash
# Bandit scanner wrapper — Python SAST
# Usage: bandit.sh [--scope-file <file>]
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

FINDINGS_FILE="${OUTPUT_DIR}/bandit-findings.jsonl"
> "$FINDINGS_FILE"

# Check for Python files
py_files_exist=false
if [[ -n "$SCOPE_FILE" ]] && [[ -f "$SCOPE_FILE" ]]; then
  grep -q '\.py$' "$SCOPE_FILE" 2>/dev/null && py_files_exist=true
else
  find . -name "*.py" -maxdepth 4 2>/dev/null | head -1 &>/dev/null && py_files_exist=true
fi

if ! $py_files_exist; then
  log_info "No Python files found, skipping Bandit"
  exit 0
fi

log_step "Running Bandit (Python SAST)..."

RAW_OUTPUT=$(mktemp /tmp/cg-bandit-XXXXXX.json)
EXIT_CODE=0

BANDIT_ARGS=("-r" "." "-f" "json" "-q")

# Scope filtering
if [[ -n "$SCOPE_FILE" ]] && [[ -f "$SCOPE_FILE" ]] && [[ -s "$SCOPE_FILE" ]]; then
  py_files=$(grep '\.py$' "$SCOPE_FILE" | tr '\n' ' ')
  if [[ -n "$py_files" ]]; then
    BANDIT_ARGS=("-f" "json" "-q" $py_files)
  fi
fi

CONTAINER_SVC=$(get_container_service_for_tool "bandit" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" bandit "${BANDIT_ARGS[@]}" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists bandit; then
  bandit "${BANDIT_ARGS[@]}" > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "Bandit not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for result in data.get('results', []):
        sev = result.get('issue_severity', 'MEDIUM').lower()
        finding = {
            'tool': 'bandit',
            'severity': sev if sev in ('high','medium','low') else 'medium',
            'rule': result.get('test_id', ''),
            'message': result.get('issue_text', ''),
            'file': result.get('filename', ''),
            'line': result.get('line_number', 0),
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
  log_warn "Bandit: found $count issue(s)"
else
  log_ok "Bandit: no issues found"
fi

echo "$FINDINGS_FILE"
