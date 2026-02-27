#!/usr/bin/env bash
# pip-audit wrapper — Python dependency vulnerability scanning
# Usage: pip-audit.sh [--autofix]
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

FINDINGS_FILE="${OUTPUT_DIR}/pip-audit-findings.jsonl"
> "$FINDINGS_FILE"

# Check for Python project markers
if ! [[ -f requirements.txt ]] && ! [[ -f pyproject.toml ]] && ! [[ -f setup.py ]] && ! [[ -f Pipfile ]]; then
  log_info "No Python dependency files found, skipping pip-audit"
  exit 0
fi

log_step "Running pip-audit (Python dependency vulnerabilities)..."

RAW_OUTPUT=$(mktemp /tmp/cg-pip-audit-XXXXXX.json)
EXIT_CODE=0

PIP_AUDIT_ARGS=("--format" "json" "--output" "$RAW_OUTPUT")
$AUTOFIX && PIP_AUDIT_ARGS+=("--fix")

# Determine requirements source
if [[ -f requirements.txt ]]; then
  PIP_AUDIT_ARGS+=("-r" "requirements.txt")
fi

CONTAINER_SVC=$(get_container_service_for_tool "pip-audit" 2>/dev/null || true)

if [[ -n "$CONTAINER_SVC" ]]; then
  log_info "Running in project container ($CONTAINER_SVC)"
  $(get_compose_cmd) exec -T "$CONTAINER_SVC" pip-audit "${PIP_AUDIT_ARGS[@]}" \
    2>/dev/null || EXIT_CODE=$?
elif cmd_exists pip-audit; then
  pip-audit "${PIP_AUDIT_ARGS[@]}" 2>/dev/null || EXIT_CODE=$?
else
  log_warn "pip-audit not available, skipping"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    deps = data.get('dependencies', [])
    for dep in deps:
        for vuln in dep.get('vulns', []):
            finding = {
                'tool': 'pip-audit',
                'severity': 'high' if 'CRITICAL' in vuln.get('description','').upper() or 'HIGH' in vuln.get('description','').upper() else 'medium',
                'rule': vuln.get('id', ''),
                'message': f\"{dep.get('name','')}=={dep.get('version','')}: {vuln.get('description', vuln.get('id',''))[:200]}\",
                'file': 'requirements.txt',
                'line': 0,
                'autoFixable': vuln.get('fix_versions', []) != [],
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
  log_warn "pip-audit: found $count vulnerability(s)"
  $AUTOFIX && log_info "Auto-fix was applied where possible"
else
  log_ok "pip-audit: no vulnerabilities found"
fi

echo "$FINDINGS_FILE"
