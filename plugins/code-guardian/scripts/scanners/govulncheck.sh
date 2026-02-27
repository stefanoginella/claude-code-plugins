#!/usr/bin/env bash
# govulncheck wrapper — Go vulnerability checking
# Usage: govulncheck.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

FINDINGS_FILE="${OUTPUT_DIR}/govulncheck-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f go.mod ]]; then
  log_info "No go.mod found, skipping govulncheck"
  exit 0
fi

log_step "Running govulncheck (Go vulnerability check)..."

RAW_OUTPUT=$(mktemp /tmp/cg-govulncheck-XXXXXX.json)
EXIT_CODE=0

CONTAINER_SVC=$(get_container_service_for_tool "govulncheck" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" govulncheck -json ./... \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists govulncheck; then
  govulncheck -json ./... > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "govulncheck not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    vulns_seen = set()
    with open('$RAW_OUTPUT') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            obj = json.loads(line)
            if 'osv' in obj.get('finding', {}):
                osv = obj['finding']['osv']
                if osv in vulns_seen: continue
                vulns_seen.add(osv)
            elif 'osv' in obj:
                entry = obj['osv']
                vuln_id = entry.get('id', '')
                if vuln_id in vulns_seen: continue
                vulns_seen.add(vuln_id)
                aliases = entry.get('aliases', [])
                summary = entry.get('summary', '')
                affected = entry.get('affected', [{}])
                pkg = affected[0].get('package', {}).get('name', '') if affected else ''
                finding = {
                    'tool': 'govulncheck',
                    'severity': 'high',
                    'rule': vuln_id,
                    'message': f'{pkg}: {summary}',
                    'file': 'go.mod',
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
  log_warn "govulncheck: found $count vulnerability(s)"
else
  log_ok "govulncheck: no vulnerabilities found"
fi

echo "$FINDINGS_FILE"
