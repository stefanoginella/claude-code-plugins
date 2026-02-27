#!/usr/bin/env bash
# Brakeman scanner wrapper — Ruby on Rails SAST
# Usage: brakeman.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

FINDINGS_FILE="${OUTPUT_DIR}/brakeman-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f config/routes.rb ]]; then
  log_info "No Rails app detected, skipping Brakeman"
  exit 0
fi

log_step "Running Brakeman (Rails SAST)..."

RAW_OUTPUT=$(mktemp /tmp/cg-brakeman-XXXXXX.json)
EXIT_CODE=0

DOCKER_IMAGE="presidentbeef/brakeman:latest"

CONTAINER_SVC=$(get_container_service_for_tool "brakeman" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" brakeman --format json --quiet --no-pager \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif docker_available; then
  docker run --rm -v "$(pwd):/code" \
    "$DOCKER_IMAGE" --format json --quiet --no-pager /code \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists brakeman; then
  brakeman --format json --quiet --no-pager > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "Brakeman not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for warning in data.get('warnings', []):
        conf_map = {'High': 'high', 'Medium': 'medium', 'Weak': 'low'}
        sev = conf_map.get(warning.get('confidence', 'Medium'), 'medium')
        finding = {
            'tool': 'brakeman',
            'severity': sev,
            'rule': warning.get('warning_type', ''),
            'message': warning.get('message', ''),
            'file': warning.get('file', ''),
            'line': warning.get('line', 0) or 0,
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
  log_warn "Brakeman: found $count issue(s)"
else
  log_ok "Brakeman: no issues found"
fi

echo "$FINDINGS_FILE"
