#!/usr/bin/env bash
# cargo-audit wrapper — Rust dependency vulnerability scanning
# Usage: cargo-audit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

FINDINGS_FILE="${OUTPUT_DIR}/cargo-audit-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f Cargo.lock ]]; then
  log_info "No Cargo.lock found, skipping cargo-audit"
  exit 0
fi

log_step "Running cargo-audit (Rust dependency vulnerabilities)..."

RAW_OUTPUT=$(mktemp /tmp/cg-cargo-audit-XXXXXX.json)
EXIT_CODE=0

if cmd_exists cargo-audit; then
  cargo audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
elif cmd_exists cargo && cargo audit --version &>/dev/null; then
  cargo audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "cargo-audit not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Detect tool failure: non-zero exit with no usable output
if [[ $EXIT_CODE -ne 0 ]] && { [[ ! -f "$RAW_OUTPUT" ]] || [[ ! -s "$RAW_OUTPUT" ]]; }; then
  log_error "cargo-audit failed (exit code $EXIT_CODE)"
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
    vulns = data.get('vulnerabilities', {}).get('list', [])
    for vuln in vulns:
        adv = vuln.get('advisory', {})
        pkg = vuln.get('package', {})
        finding = {
            'tool': 'cargo-audit',
            'severity': 'high',
            'rule': adv.get('id', ''),
            'message': f\"{pkg.get('name','')}@{pkg.get('version','')}: {adv.get('title','')}\",
            'file': 'Cargo.lock',
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
  log_warn "cargo-audit: found $count vulnerability(s)"
else
  log_ok "cargo-audit: no vulnerabilities found"
fi

echo "$FINDINGS_FILE"
