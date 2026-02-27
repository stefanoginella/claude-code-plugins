#!/usr/bin/env bash
# bundler-audit wrapper — Ruby dependency vulnerability scanning
# Usage: bundler-audit.sh [--autofix]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

AUTOFIX=false
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autofix) AUTOFIX=true; shift ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/bundler-audit-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f Gemfile.lock ]]; then
  log_info "No Gemfile.lock found, skipping bundler-audit"
  exit 0
fi

log_step "Running bundler-audit (Ruby dependency vulnerabilities)..."

RAW_OUTPUT=$(mktemp /tmp/cg-bundler-audit-XXXXXX.txt)
EXIT_CODE=0

CONTAINER_SVC=$(get_container_service_for_tool "bundle-audit" 2>/dev/null || true)
[[ -z "$CONTAINER_SVC" ]] && CONTAINER_SVC=$(get_container_service_for_tool "bundler-audit" 2>/dev/null || true)

if $AUTOFIX; then
  if [[ -n "$CONTAINER_SVC" ]]; then
    $(get_compose_cmd) exec -T "$CONTAINER_SVC" bundle-audit update 2>/dev/null || true
  elif cmd_exists bundle-audit; then
    bundle-audit update 2>/dev/null || true
  fi
fi

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" bundle-audit check --format json \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists bundle-audit; then
  bundle-audit check --format json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists bundler-audit; then
  bundler-audit check --format json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "bundler-audit not available, skipping"
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
        adv = result.get('advisory', {})
        gem = result.get('gem', {})
        finding = {
            'tool': 'bundler-audit',
            'severity': adv.get('criticality', 'medium'),
            'rule': adv.get('id', adv.get('cve', '')),
            'message': f\"{gem.get('name','')}@{gem.get('version','')}: {adv.get('title','')}\",
            'file': 'Gemfile.lock',
            'line': 0,
            'autoFixable': False,
            'category': 'dependency'
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
  log_warn "bundler-audit: found $count vulnerability(s)"
else
  log_ok "bundler-audit: no vulnerabilities found"
fi

echo "$FINDINGS_FILE"
