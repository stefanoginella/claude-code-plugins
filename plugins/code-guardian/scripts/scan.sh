#!/usr/bin/env bash
# Main scan orchestrator — runs relevant scanners based on detected stack
# Usage: scan.sh --stack-json <file> --scope <scope> [--base-ref <ref>] [--autofix] [--tools-json <file>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tool-registry.sh"

STACK_JSON=""
TOOLS_JSON=""
SCOPE="codebase"
BASE_REF=""
AUTOFIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-json) STACK_JSON="$2"; shift 2 ;;
    --tools-json) TOOLS_JSON="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --base-ref) BASE_REF="$2"; shift 2 ;;
    --autofix) AUTOFIX=true; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$STACK_JSON" ]] || ! [[ -f "$STACK_JSON" ]]; then
  log_error "Stack JSON file required (--stack-json)"
  exit 1
fi

# Create output directory for this scan
SCAN_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCAN_OUTPUT_DIR=$(mktemp -d /tmp/code-guardian-scan-${SCAN_TIMESTAMP}-XXXXXX)
export SCAN_OUTPUT_DIR

log_step "Security scan started"
log_info "Scope: $SCOPE"
[[ -n "$BASE_REF" ]] && log_info "Base ref: $BASE_REF"
$AUTOFIX && log_info "Mode: YOLO (autofix enabled)"
echo "" >&2

# Get scope file
SCOPE_FILE=""
if [[ "$SCOPE" != "codebase" ]]; then
  SCOPE_FILE=$(write_scope_file "$SCOPE" "$BASE_REF")
  file_count=$(wc -l < "$SCOPE_FILE" | tr -d ' ')
  log_info "Files in scope: $file_count"
  if [[ "$file_count" -eq 0 ]]; then
    log_ok "No files in scope — nothing to scan"
    echo "{\"scanDir\":\"$SCAN_OUTPUT_DIR\",\"findings\":[],\"summaries\":[],\"scope\":\"$SCOPE\",\"fileCount\":0}"
    exit 0
  fi
fi

# Parse stack info
parse_json_array() {
  echo "$1" | tr -d '[]"' | tr ',' '\n' | tr -d ' ' | grep -v '^$'
}

stack_data=$(cat "$STACK_JSON")
languages=$(echo "$stack_data" | grep '"languages"' | sed 's/.*: *//;s/,$//')
has_docker=$(echo "$stack_data" | grep '"docker"' | sed 's/.*: *//;s/,$//' | tr -d ' ')
iac_tools=$(echo "$stack_data" | grep '"iacTools"' | sed 's/.*: *//;s/,$//')

# Parse available tools from tools JSON
available_tools=()
if [[ -n "$TOOLS_JSON" ]] && [[ -f "$TOOLS_JSON" ]]; then
  while IFS= read -r tool; do
    [[ -n "$tool" ]] && available_tools+=("$tool")
  done < <(python3 -c "
import json, sys
data = json.load(open('$TOOLS_JSON'))
for t in data.get('available', []):
    print(t)
" 2>/dev/null || true)
fi

# Determine which scanners to run
scanners_to_run=()

# Collect needed tools from stack
needed_tools=()
while IFS= read -r lang; do
  [[ -z "$lang" ]] && continue
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    # Deduplicate
    found=false
    for existing in "${needed_tools[@]+"${needed_tools[@]}"}"; do
      [[ "$existing" == "$tool" ]] && found=true && break
    done
    $found || needed_tools+=("$tool")
  done < <(get_tools_for_stack "$lang" | tr ' ' '\n')
done < <(parse_json_array "$languages")

# Add Docker tools
if [[ "$has_docker" == "true" ]]; then
  for tool in $(get_tools_for_stack "docker"); do
    found=false
    for existing in "${needed_tools[@]+"${needed_tools[@]}"}"; do
      [[ "$existing" == "$tool" ]] && found=true && break
    done
    $found || needed_tools+=("$tool")
  done
fi

# Add IaC tools
if echo "$iac_tools" | grep -q '[a-z]'; then
  for tool in $(get_tools_for_stack "iac"); do
    found=false
    for existing in "${needed_tools[@]+"${needed_tools[@]}"}"; do
      [[ "$existing" == "$tool" ]] && found=true && break
    done
    $found || needed_tools+=("$tool")
  done
fi

# Filter to available tools only
for tool in "${needed_tools[@]}"; do
  if [[ ${#available_tools[@]} -gt 0 ]]; then
    for avail in "${available_tools[@]}"; do
      if [[ "$avail" == "$tool" ]]; then
        scanners_to_run+=("$tool")
        break
      fi
    done
  else
    # No tools JSON provided — check availability directly
    status=$(check_tool_availability "$tool")
    [[ "$status" != "unavailable" ]] && scanners_to_run+=("$tool")
  fi
done

if [[ ${#scanners_to_run[@]} -eq 0 ]]; then
  log_error "No security tools available to run"
  exit 1
fi

log_info "Scanners to run: ${scanners_to_run[*]}"
echo "" >&2

# ── Run each scanner ──────────────────────────────────────────────────
ALL_FINDINGS=()
ALL_SUMMARIES=()

for scanner in "${scanners_to_run[@]}"; do
  SCANNER_SCRIPT="${SCRIPT_DIR}/scanners/${scanner}.sh"

  if ! [[ -f "$SCANNER_SCRIPT" ]]; then
    log_warn "No scanner script for: $scanner"
    continue
  fi

  SCANNER_ARGS=()
  [[ -n "$SCOPE_FILE" ]] && SCANNER_ARGS+=("--scope-file" "$SCOPE_FILE")
  $AUTOFIX && SCANNER_ARGS+=("--autofix")

  # Run scanner (don't fail the whole scan if one scanner fails)
  findings_file=""
  if findings_file=$(bash "$SCANNER_SCRIPT" "${SCANNER_ARGS[@]}" 2>&1 | tail -1) && \
     [[ -n "$findings_file" ]] && [[ -f "$findings_file" ]]; then
    ALL_FINDINGS+=("$findings_file")
    # Create summary
    summary=$(create_summary "$findings_file" "$scanner")
    ALL_SUMMARIES+=("$summary")
  else
    log_warn "Scanner $scanner failed or produced no output"
  fi

  echo "" >&2
done

# ── Merge all findings ────────────────────────────────────────────────
MERGED_FILE="${SCAN_OUTPUT_DIR}/all-findings.jsonl"
> "$MERGED_FILE"
for f in "${ALL_FINDINGS[@]+"${ALL_FINDINGS[@]}"}"; do
  if [[ -f "$f" ]] && [[ -s "$f" ]]; then
    cat "$f" >> "$MERGED_FILE"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────
total=$(wc -l < "$MERGED_FILE" | tr -d ' ')
high=$(grep -c '"severity":"high"' "$MERGED_FILE" 2>/dev/null || echo 0)
medium=$(grep -c '"severity":"medium"' "$MERGED_FILE" 2>/dev/null || echo 0)
low=$(grep -c '"severity":"low"' "$MERGED_FILE" 2>/dev/null || echo 0)

echo "" >&2
log_step "Scan complete"
echo "" >&2
if [[ "$total" -gt 0 ]]; then
  log_warn "Total findings: $total (high: $high, medium: $medium, low: $low)"
else
  log_ok "No security issues found!"
fi

# Clean up scope file
[[ -n "$SCOPE_FILE" ]] && rm -f "$SCOPE_FILE"

# Output scan results as JSON
summaries_json="["
for i in "${!ALL_SUMMARIES[@]}"; do
  [[ $i -gt 0 ]] && summaries_json+=","
  summaries_json+="${ALL_SUMMARIES[$i]}"
done
summaries_json+="]"

cat <<EOF
{
  "scanDir": "$SCAN_OUTPUT_DIR",
  "findingsFile": "$MERGED_FILE",
  "scope": "$SCOPE",
  "baseRef": "$BASE_REF",
  "autofix": $AUTOFIX,
  "totalFindings": $total,
  "high": $high,
  "medium": $medium,
  "low": $low,
  "scannersRun": $(printf '["%s"]' "$(IFS='","'; echo "${scanners_to_run[*]}")"),
  "summaries": $summaries_json
}
EOF
