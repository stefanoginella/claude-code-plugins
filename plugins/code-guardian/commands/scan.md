---
name: security-guardian-scan
description: Run security scan on the codebase using detected stack-appropriate tools
argument-hint: "[--mode interactive|yolo] [--scope codebase|uncommitted|unpushed] [--refresh]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Security Scan Command

Run a comprehensive security scan using open-source CLI tools appropriate for the project's detected stack. Tools run via Docker when available, falling back to local binaries.

## Execution Flow

### Step 1: Parse Arguments

Check if the user provided arguments. Parse `--mode` (interactive or yolo), `--scope` (codebase, uncommitted, unpushed), and `--refresh` from the command arguments: `$ARGUMENTS`.

If mode or scope not provided, ask the user:

Use AskUserQuestion to ask:
1. **Mode**: "Which scan mode?" — interactive (review findings and choose what to fix) or yolo (auto-fix everything possible, then fix the rest)
2. **Scope**: "What scope to scan?" — codebase (all tracked files), uncommitted (staged + unstaged + untracked — all local uncommitted work), unpushed (all commits not yet pushed to remote)
3. If scope is "unpushed", also ask: "Compare against which base?" — options: default branch (origin/main or origin/master), remote tracking branch, or custom ref

### Step 1.5: Check Cache

Unless `--refresh` was passed, try to load cached detection results:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-state.sh --read --max-age 86400
```

- **Exit 0** (fresh cache): Parse the returned JSON to extract `stack` and `tools` fields. Use these as the stack and tools data — tell the user "Using cached detection results" and **skip Steps 2–3**, jumping directly to Step 4.
- **Exit 2** (stale): Log "Cached results are stale, re-detecting..." and continue to Steps 2–3.
- **Exit 1** (missing/invalid): Continue to Steps 2–3 (normal behavior).

If `--refresh` was passed, skip the cache check entirely and proceed to Steps 2–3.

### Step 2: Detect Stack

Run the stack detection script:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh .
```

Display the detected stack to the user in a concise summary. Show languages, frameworks, Docker presence, CI systems found.

### Step 3: Check Tool Availability

Pipe the stack JSON into the tool checker:
```bash
echo '<stack_json>' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-tools.sh
```

Report which tools are available (Docker or local) and which are missing.

### Step 3.5: Write Cache

If Steps 2–3 ran (i.e., cache was not used), save the fresh detection results for future commands:

```bash
echo '<stack_json>' > /tmp/cg-stack.json
echo '<tools_json>' > /tmp/cg-tools.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-state.sh --write \
  --stack-file /tmp/cg-stack.json --tools-file /tmp/cg-tools.json
```

**If mode is INTERACTIVE and tools are missing**:
For each missing tool, use AskUserQuestion with these options:
1. **Install now** — Run the install command (Docker pull preferred, otherwise package manager)
2. **Show manual instructions** — Print install commands for all methods so the dev can handle it later. Do NOT run anything.
3. **Skip this tool** — Proceed without it. The scan will note it was skipped.

If multiple tools are missing, offer a batch option first: "Install all", "Show all instructions", "Skip all", or "Handle one by one".

**If mode is YOLO and tools are missing**:
Skip all missing tools automatically — do NOT prompt. Print a brief summary of what was skipped and why (not installed, no Docker image available). Include install instructions for each skipped tool in the final report so the dev can install them later and re-run. The scan proceeds with whatever tools ARE available.

### Step 4: Run Security Scan

Save the stack JSON and tools JSON to temp files, then run the orchestrator:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh \
  --stack-json /tmp/cg-stack.json \
  --tools-json /tmp/cg-tools.json \
  --scope <scope> \
  [--base-ref <ref>] \
  [--autofix]  # only in yolo mode
```

Pass `--autofix` flag ONLY if mode is yolo.

### Step 5: Process Results

Read the merged findings file from the scan output. The scan returns JSON with `findingsFile` path.

Read the findings file:
```bash
cat <findingsFile>
```

Each line is a JSON finding with: tool, severity, rule, message, file, line, autoFixable, category.

### Step 6: Handle Findings

**If no findings**: Report success. Suggest the user consider adding CI scanning if none detected (reference `/code-guardian:code-guardian-ci`).

**If mode is YOLO**:
1. Report what was auto-fixed by the tools (semgrep --autofix, eslint --fix, npm audit fix, etc.)
2. For remaining findings that tools couldn't auto-fix:
   - Read each affected file
   - Apply the fix based on the finding details (rule, message, line)
   - Focus on high and medium severity first
3. After fixing, re-run the scan to verify fixes
4. Report final status with these sections:
   - **Auto-fixed**: What the CLI tools fixed automatically
   - **AI-fixed**: What Claude fixed with code-level changes
   - **Remaining**: Anything that couldn't be fixed (with explanation)
   - **Skipped tools**: Any tools that weren't available, with install instructions for each so the dev can install them and re-run for broader coverage

**If mode is INTERACTIVE**:
1. Present findings grouped by severity (high first), then by category
2. For each severity group, show a summary table:
   ```
   | # | Severity | Tool | Rule | File:Line | Auto-fixable |
   ```
3. Ask the user what to fix:
   - "Fix all high severity"
   - "Fix all auto-fixable"
   - "Fix specific findings (by number)"
   - "Skip and just report"
4. For selected findings:
   - If auto-fixable: re-run the relevant scanner with --autofix
   - If not auto-fixable: read the file, understand the vulnerability, and apply a code fix
5. After fixing, report what was done

### Step 7: CI Recommendations

If the project has no CI security scanning configured (or has CI but no security jobs), suggest adding security to CI. Briefly mention `/code-guardian:code-guardian-ci` for generating the config.

## Important Notes

- Use cached detection results when available; run `detect-stack.sh` fresh when cache is missing, stale, or `--refresh` is passed
- Never modify files outside the project directory
- For secret findings, NEVER display the actual secret value in output
- When fixing code, explain what vulnerability you're addressing and why the fix works
- If a finding is a false positive, explain why and suggest adding it to the tool's ignore list
- Prefer minimal, targeted fixes over large refactors
- After auto-fixes, always verify the code still compiles/passes basic checks
