---
name: code-guardian-setup
description: Check and install security scanning tools for the detected stack
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Security Tools Setup

Check which security tools are available for the project's detected stack and help install missing ones.

## Execution Flow

### Step 1: Detect Stack

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh .
```

Display detected stack summary.

### Step 2: Check Tools

```bash
echo '<stack_json>' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-tools.sh
```

### Step 2.5: Cache Detection Results

Save the stack and tools detection results so that future scan/ci commands can reuse them without re-detecting:

```bash
echo '<stack_json>' > /tmp/cg-stack.json
echo '<tools_json>' > /tmp/cg-tools.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-state.sh --write \
  --stack-file /tmp/cg-stack.json --tools-file /tmp/cg-tools.json
```

### Step 3: Present Report

Show a clear table of all needed tools:

```
| Tool          | Category    | Status      | How Available        |
|---------------|-------------|-------------|----------------------|
| semgrep       | SAST        | Available   | Docker image         |
| gitleaks      | Secrets     | Available   | Local binary         |
| trivy         | Vuln scan   | MISSING     | —                    |
| hadolint      | Container   | Available   | Docker image         |
```

### Step 4: Handle Missing Tools

If there are missing tools, present them one by one (or grouped if there are many). For each missing tool, use AskUserQuestion with these options:

1. **Install now** — Run the install command (Docker pull if Docker available, otherwise package manager)
2. **Show manual instructions** — Print the install commands for all available methods (Docker pull, brew/pip/npm/cargo, direct download) so the dev can run them on their own time. Do NOT run anything.
3. **Skip this tool** — Skip it entirely. The scan will run without this tool and note it in the report.

If multiple tools are missing, also offer a batch option upfront:
- "Install all missing tools"
- "Show manual instructions for all"
- "Skip all missing tools"
- "Handle one by one"

Run only the installation commands the user explicitly approves.

### Step 5: Verify

After any installations, re-run the tool check to verify everything is working.

Report final status as a table showing:
- Available tools (Docker or local) — ready to use
- Skipped tools — will be excluded from scans
- Failed installations — with troubleshooting hints

### Step 5.5: Update Cache

After verification, overwrite the cache with the updated tools data (post-install results):

```bash
echo '<stack_json>' > /tmp/cg-stack.json
echo '<verified_tools_json>' > /tmp/cg-tools.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-state.sh --write \
  --stack-file /tmp/cg-stack.json --tools-file /tmp/cg-tools.json
```

Tell the user: "Tool availability cached. Future scans will reuse these results (valid for 24 hours)."

## Important Notes

- Always prefer Docker images when Docker is available (consistent versions, no system pollution)
- Never install tools without user confirmation
- Show the exact commands that will be run before executing them
- After installation, verify the tool works by running its version/help command
- Skipped tools are fine — the scan will work with whatever is available and note what was skipped
