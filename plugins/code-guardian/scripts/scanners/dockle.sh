#!/usr/bin/env bash
# Dockle wrapper — container image best practice linter
# Usage: dockle.sh [--target <image_name>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

TARGET=""
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/dockle-findings.jsonl"
> "$FINDINGS_FILE"

if [[ -z "$TARGET" ]]; then
  log_info "No Docker image target specified, skipping Dockle"
  exit 0
fi

log_step "Running Dockle (container image lint: $TARGET)..."

RAW_OUTPUT=$(mktemp /tmp/cg-dockle-XXXXXX.json)
EXIT_CODE=0

DOCKER_IMAGE="goodwithtech/dockle:latest"

CONTAINER_SVC=$(get_container_service_for_tool "dockle" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" dockle --format json "$TARGET" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif docker_available && docker image inspect "$TARGET" &>/dev/null; then
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    "$DOCKER_IMAGE" --format json "$TARGET" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists dockle; then
  dockle --format json "$TARGET" > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "Dockle not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for detail in data.get('details', []):
        sev_map = {'FATAL': 'high', 'WARN': 'medium', 'INFO': 'low', 'SKIP': 'info', 'PASS': 'info'}
        finding = {
            'tool': 'dockle',
            'severity': sev_map.get(detail.get('level', 'INFO'), 'info'),
            'rule': detail.get('code', ''),
            'message': detail.get('title', ''),
            'file': '$TARGET',
            'line': 0,
            'autoFixable': False,
            'category': 'container'
        }
        if finding['severity'] != 'info':
            print(json.dumps(finding))
except Exception as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
" > "$FINDINGS_FILE"
  fi
fi

rm -f "$RAW_OUTPUT"

count=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$count" -gt 0 ]]; then
  log_warn "Dockle: found $count issue(s)"
else
  log_ok "Dockle: no issues found"
fi

echo "$FINDINGS_FILE"
