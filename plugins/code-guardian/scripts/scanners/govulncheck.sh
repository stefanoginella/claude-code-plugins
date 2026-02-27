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

if cmd_exists govulncheck; then
  govulncheck -json ./... > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "govulncheck not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Detect tool failure: non-zero exit with no usable output
if [[ $EXIT_CODE -ne 0 ]] && { [[ ! -f "$RAW_OUTPUT" ]] || [[ ! -s "$RAW_OUTPUT" ]]; }; then
  log_error "govulncheck failed (exit code $EXIT_CODE)"
  rm -f "$RAW_OUTPUT"
  echo "$FINDINGS_FILE"
  exit 2
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    osv_entries = {}  # vuln_id -> osv entry data
    finding_ids = set()  # vuln IDs confirmed as actually called
    with open('$RAW_OUTPUT') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            obj = json.loads(line)
            # Collect OSV entries (vulnerability metadata)
            if 'osv' in obj:
                entry = obj['osv']
                vuln_id = entry.get('id', '')
                if vuln_id:
                    osv_entries[vuln_id] = entry
            # Collect findings (confirmed vulnerable call sites)
            if 'finding' in obj:
                f_osv = obj['finding'].get('osv', '')
                if f_osv:
                    finding_ids.add(f_osv)
    # Emit findings: prefer confirmed findings, fall back to all OSV entries
    emitted = set()
    for vuln_id, entry in osv_entries.items():
        if vuln_id in emitted: continue
        emitted.add(vuln_id)
        summary = entry.get('summary', '')
        affected = entry.get('affected', [{}])
        pkg = affected[0].get('package', {}).get('name', '') if affected else ''
        # Confirmed findings (actually called) get high severity;
        # unconfirmed (imported but not called) get medium
        sev = 'high' if vuln_id in finding_ids else 'medium'
        finding = {
            'tool': 'govulncheck',
            'severity': sev,
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
