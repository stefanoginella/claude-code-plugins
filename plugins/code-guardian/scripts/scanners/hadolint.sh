#!/usr/bin/env bash
# Hadolint scanner wrapper — Dockerfile linting
# Usage: hadolint.sh [--target <Dockerfile>]
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

FINDINGS_FILE="${OUTPUT_DIR}/hadolint-findings.jsonl"
> "$FINDINGS_FILE"

# Find all Dockerfiles
DOCKERFILES=()
if [[ -n "$TARGET" ]]; then
  DOCKERFILES=("$TARGET")
else
  while IFS= read -r -d '' f; do
    DOCKERFILES+=("$f")
  done < <(find . -maxdepth 3 \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.dockerfile" \) -print0 2>/dev/null)
fi

if [[ ${#DOCKERFILES[@]} -eq 0 ]]; then
  log_info "No Dockerfiles found, skipping Hadolint"
  exit 0
fi

log_step "Running Hadolint (Dockerfile linting)..."

DOCKER_IMAGE="hadolint/hadolint:latest"

for dockerfile in "${DOCKERFILES[@]}"; do
  RAW_OUTPUT=$(mktemp /tmp/cg-hadolint-XXXXXX.json)

  CONTAINER_SVC=$(get_container_service_for_tool "hadolint" 2>/dev/null || true)

  if [[ -n "$CONTAINER_SVC" ]]; then
    log_info "Running in project container ($CONTAINER_SVC)"
    $(get_compose_cmd) exec -T "$CONTAINER_SVC" hadolint --format json "$dockerfile" \
      > "$RAW_OUTPUT" 2>/dev/null || true
  elif docker_available; then
    docker run --rm -i "$DOCKER_IMAGE" hadolint --format json - \
      < "$dockerfile" > "$RAW_OUTPUT" 2>/dev/null || true
  elif cmd_exists hadolint; then
    hadolint --format json "$dockerfile" > "$RAW_OUTPUT" 2>/dev/null || true
  else
    log_warn "Hadolint not available, skipping"
    rm -f "$RAW_OUTPUT"
    exit 0
  fi

  if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
    if cmd_exists python3; then
      python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for item in data:
        sev_map = {'error': 'high', 'warning': 'medium', 'info': 'low', 'style': 'info'}
        finding = {
            'tool': 'hadolint',
            'severity': sev_map.get(item.get('level', 'info'), 'info'),
            'rule': item.get('code', ''),
            'message': item.get('message', ''),
            'file': '$dockerfile',
            'line': item.get('line', 0),
            'autoFixable': False,
            'category': 'container'
        }
        print(json.dumps(finding))
except Exception as e:
    pass
" >> "$FINDINGS_FILE"
    fi
  fi
  rm -f "$RAW_OUTPUT"
done

count=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$count" -gt 0 ]]; then
  log_warn "Hadolint: found $count issue(s)"
else
  log_ok "Hadolint: no issues found"
fi

echo "$FINDINGS_FILE"
