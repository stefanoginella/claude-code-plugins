#!/usr/bin/env bash
# npm/yarn/pnpm audit wrapper — JS/TS dependency vulnerability scanning
# Usage: npm-audit.sh [--autofix] [--pm npm|yarn|pnpm|bun]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

AUTOFIX=false
PM=""
OUTPUT_DIR="${SCAN_OUTPUT_DIR:-.}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autofix) AUTOFIX=true; shift ;;
    --pm) PM="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FINDINGS_FILE="${OUTPUT_DIR}/npm-audit-findings.jsonl"
> "$FINDINGS_FILE"

# Detect package manager if not specified
if [[ -z "$PM" ]]; then
  if [[ -f pnpm-lock.yaml ]]; then PM="pnpm"
  elif [[ -f yarn.lock ]]; then PM="yarn"
  elif [[ -f bun.lockb ]] || [[ -f bun.lock ]]; then PM="bun"
  elif [[ -f package-lock.json ]] || [[ -f package.json ]]; then PM="npm"
  fi
fi

if [[ -z "$PM" ]] || ! [[ -f package.json ]]; then
  log_info "No JS/TS package manager detected, skipping npm audit"
  exit 0
fi

log_step "Running $PM audit (dependency vulnerabilities)..."

RAW_OUTPUT=$(mktemp /tmp/cg-npm-audit-XXXXXX.json)
EXIT_CODE=0

case "$PM" in
  npm)
    if $AUTOFIX; then
      npm audit fix --force 2>/dev/null || true
      log_info "Ran npm audit fix --force"
    fi
    npm audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
    ;;
  yarn)
    yarn audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
    ;;
  pnpm)
    pnpm audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
    ;;
  bun)
    # Bun doesn't have built-in audit; use npm audit if available
    if cmd_exists npm; then
      npm audit --json > "$RAW_OUTPUT" 2>/dev/null || EXIT_CODE=$?
    else
      log_info "Bun has no built-in audit and npm not available, skipping"
      rm -f "$RAW_OUTPUT"
      exit 0
    fi
    ;;
esac

# Detect tool failure: non-zero exit with no usable output
if [[ $EXIT_CODE -ne 0 ]] && { [[ ! -f "$RAW_OUTPUT" ]] || [[ ! -s "$RAW_OUTPUT" ]]; }; then
  log_error "$PM audit failed (exit code $EXIT_CODE)"
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
    vulns = data.get('vulnerabilities', {})
    for name, vuln in vulns.items():
        sev_map = {'critical': 'high', 'high': 'high', 'moderate': 'medium', 'low': 'low', 'info': 'info'}
        sev = sev_map.get(vuln.get('severity', 'info'), 'info')
        finding = {
            'tool': 'npm-audit',
            'severity': sev,
            'rule': name,
            'message': f\"{name}@{vuln.get('range','')}: {vuln.get('title', vuln.get('name',''))}\",
            'file': 'package.json',
            'line': 0,
            'autoFixable': vuln.get('fixAvailable', False) is True or isinstance(vuln.get('fixAvailable'), dict),
            'category': 'dependency'
        }
        print(json.dumps(finding))
except Exception as e:
    # yarn audit uses a different JSON format (one JSON object per line)
    try:
        with open('$RAW_OUTPUT') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                obj = json.loads(line)
                if obj.get('type') == 'auditAdvisory':
                    adv = obj.get('data', {}).get('advisory', {})
                    sev_map = {'critical': 'high', 'high': 'high', 'moderate': 'medium', 'low': 'low', 'info': 'info'}
                    finding = {
                        'tool': 'npm-audit',
                        'severity': sev_map.get(adv.get('severity', 'info'), 'info'),
                        'rule': adv.get('module_name', ''),
                        'message': adv.get('title', ''),
                        'file': 'package.json',
                        'line': 0,
                        'autoFixable': False,
                        'category': 'dependency'
                    }
                    print(json.dumps(finding))
    except Exception:
        pass
" > "$FINDINGS_FILE"
  fi
fi

rm -f "$RAW_OUTPUT"

count=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$count" -gt 0 ]]; then
  log_warn "$PM audit: found $count vulnerability(s)"
  $AUTOFIX && log_info "Auto-fix was applied where possible"
else
  log_ok "$PM audit: no vulnerabilities found"
fi

echo "$FINDINGS_FILE"
