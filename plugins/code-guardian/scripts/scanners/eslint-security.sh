#!/usr/bin/env bash
# ESLint security plugin wrapper — JS/TS security linting with autofix
# Usage: eslint-security.sh [--autofix] [--scope-file <file>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

AUTOFIX=false
SCOPE_FILE=""
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autofix) AUTOFIX=true; shift ;;
    --scope-file) SCOPE_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/eslint-security-findings.jsonl"
> "$FINDINGS_FILE"

if ! [[ -f package.json ]]; then
  log_info "No package.json found, skipping ESLint security"
  exit 0
fi

# Check if eslint is available (project container, local node_modules, or global)
ESLINT_BIN=""
ESLINT_CONTAINER_SVC=$(get_container_service_for_tool "eslint" 2>/dev/null || true)

if [[ -n "$ESLINT_CONTAINER_SVC" ]]; then
  ESLINT_BIN="eslint"  # will run via compose exec
  log_info "ESLint found in project container ($ESLINT_CONTAINER_SVC)"
elif [[ -f node_modules/.bin/eslint ]]; then
  ESLINT_BIN="node_modules/.bin/eslint"
elif cmd_exists eslint; then
  ESLINT_BIN="eslint"
fi

if [[ -z "$ESLINT_BIN" ]]; then
  log_warn "ESLint not available, skipping security lint"
  exit 0
fi

# Check if security plugin is available
has_security_plugin=false
if [[ -d node_modules/eslint-plugin-security ]]; then
  has_security_plugin=true
elif $ESLINT_BIN --print-config . 2>/dev/null | grep -q "security" 2>/dev/null; then
  has_security_plugin=true
fi

if ! $has_security_plugin; then
  log_info "eslint-plugin-security not installed, skipping. Install: npm install -D eslint-plugin-security"
  exit 0
fi

log_step "Running ESLint with security rules..."

RAW_OUTPUT=$(mktemp /tmp/cg-eslint-sec-XXXXXX.json)
EXIT_CODE=0

ESLINT_ARGS=("--format" "json" "--no-error-on-unmatched-pattern")
$AUTOFIX && ESLINT_ARGS+=("--fix")

# Determine target files
if [[ -n "$SCOPE_FILE" ]] && [[ -f "$SCOPE_FILE" ]] && [[ -s "$SCOPE_FILE" ]]; then
  js_files=$(grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' "$SCOPE_FILE" | tr '\n' ' ')
  if [[ -z "$js_files" ]]; then
    log_info "No JS/TS files in scope, skipping ESLint security"
    rm -f "$RAW_OUTPUT"
    exit 0
  fi
  ESLINT_ARGS+=($js_files)
else
  ESLINT_ARGS+=(".")
fi

if [[ -n "$ESLINT_CONTAINER_SVC" ]]; then
  $(get_compose_cmd) exec -T "$ESLINT_CONTAINER_SVC" eslint "${ESLINT_ARGS[@]}" \
    > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
else
  $ESLINT_BIN "${ESLINT_ARGS[@]}" > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
fi

if [[ -f "$RAW_OUTPUT" ]] && [[ -s "$RAW_OUTPUT" ]]; then
  if cmd_exists python3; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$RAW_OUTPUT'))
    for file_result in data:
        filepath = file_result.get('filePath', '')
        for msg in file_result.get('messages', []):
            rule_id = msg.get('ruleId', '')
            # Only include security-related rules
            if not rule_id or 'security' not in rule_id:
                continue
            sev = 'high' if msg.get('severity', 1) == 2 else 'medium'
            finding = {
                'tool': 'eslint-security',
                'severity': sev,
                'rule': rule_id,
                'message': msg.get('message', ''),
                'file': filepath,
                'line': msg.get('line', 0),
                'autoFixable': msg.get('fix') is not None,
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
  log_warn "ESLint security: found $count issue(s)"
  $AUTOFIX && log_info "Auto-fix was applied where possible"
else
  log_ok "ESLint security: no issues found"
fi

echo "$FINDINGS_FILE"
