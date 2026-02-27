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

if cmd_exists gosec; then
  gosec -fmt=json -out="$RAW_OUTPUT" ./... 2>/dev/null || EXIT_CODE=$?
elif docker_available; then
  docker run --rm -v "$(pwd):/workspace" -w /workspace \
    "$DOCKER_IMAGE" -fmt=json -out=/workspace/.gosec-output.json ./... 2>/dev/null || EXIT_CODE=$?
  [[ -f .gosec-output.json ]] && mv .gosec-output.json "$RAW_OUTPUT"
else
  log_warn "gosec not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Detect tool failure: non-zero exit with no usable output
if [[ $EXIT_CODE -ne 0 ]] && { [[ ! -f "$RAW_OUTPUT" ]] || [[ ! -s "$RAW_OUTPUT" ]]; }; then
  log_error "gosec failed (exit code $EXIT_CODE)"
  rm -f "$RAW_OUTPUT"
  echo "$FINDINGS_FILE"
  exit 2
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

# Post-filter findings to scope if scope file provided
if [[ -n "$SCOPE_FILE" ]] && [[ -f "$SCOPE_FILE" ]] && [[ -s "$FINDINGS_FILE" ]]; then
  FILTERED=$(mktemp /tmp/cg-gosec-filtered-XXXXXX.jsonl)
  python3 -c "
import json, sys
scope_files = set()
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            scope_files.add(line)
            scope_files.add(line.lstrip('./'))
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            finding = json.loads(line)
            fpath = finding.get('file', '').lstrip('./')
            if fpath in scope_files or any(fpath == s.lstrip('./') for s in scope_files):
                print(line)
        except json.JSONDecodeError:
            continue
" "$SCOPE_FILE" "$FINDINGS_FILE" > "$FILTERED"
  mv "$FILTERED" "$FINDINGS_FILE"
fi

count=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$count" -gt 0 ]]; then
  log_warn "gosec: found $count issue(s)"
else
  log_ok "gosec: no issues found"
fi

echo "$FINDINGS_FILE"
