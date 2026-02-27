---
name: code-guardian-setup
description: Check security tool availability for the detected stack and show install instructions
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# Security Tools Setup

Detect the project stack, check which security tools are available, and report what's missing with install instructions.

This command does NOT install anything — it gives you a clear picture and copy-pasteable commands.

## Execution Flow

### Step 1: Detect Stack

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh .
```

Display detected stack: languages, frameworks, package managers, Docker, CI systems, IaC tools.

### Step 2: Check Tools

```bash
echo '<stack_json>' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-tools.sh
```

### Step 3: Cache Results

Save detection results for future scan/ci commands:

```bash
echo '<stack_json>' > /tmp/cg-stack.json
echo '<tools_json>' > /tmp/cg-tools.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-state.sh --write \
  --stack-file /tmp/cg-stack.json --tools-file /tmp/cg-tools.json
```

### Step 4: Present Report

Show a clear table of all needed tools:

```
| Tool          | Category    | Status    | How Available        |
|---------------|-------------|-----------|----------------------|
| semgrep       | SAST        | Ready     | Local binary         |
| gitleaks      | Secrets     | Ready     | Docker image         |
| trivy         | Vuln scan   | MISSING   | —                    |
| hadolint      | Container   | Ready     | Docker image         |
```

### Step 5: Show Install Instructions for Missing Tools

If there are missing tools, list them with install commands for the current OS:

```
Missing tools — install any you want, then re-run this command to verify:

  trivy:
    brew install trivy

  checkov:
    pip3 install checkov

  pip-audit:
    pip3 install pip-audit
```

End with: "Scans will use whatever tools are available and skip the rest. Install what you need and run `/code-guardian:code-guardian-setup` again to verify."

If ESLint security is in the tool list, note that it requires the `eslint-plugin-security` package to be installed in the project (`npm install -D eslint-plugin-security`). Without it, the scanner will skip even if ESLint itself is available.

If all tools are available, just say so: "All recommended security tools are available. Run `/code-guardian:code-guardian-scan` to scan."

### Step 6: Show Current Configuration

Read the current config:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh --dump
```

If a config file exists (`.claude/code-guardian.config.json`), display the current settings.

If no config file exists, tell the user:
> No configuration file found. Using defaults (all available tools, full codebase scope).

Then ask with AskUserQuestion: "Would you like to configure scan defaults?"

Options:
- **Yes, configure now** — proceed to Step 7
- **No, use defaults** — done

### Step 7: Configure Scan Defaults (if requested)

Ask with AskUserQuestion (multi-select): "Which tools do you want to run by default?" — list all available tools as options.

Based on the answer, determine the config:
- If the user selected ALL available tools → don't set `tools` (default runs everything)
- If the user selected a subset → set `tools` to that list
- Also ask: "Any tools you want to permanently disable?" — list all available tools. Set `disabled` for any selected.

Write the config file `.claude/code-guardian.config.json`:

```json
{
  "tools": ["semgrep", "gitleaks", "trivy"],
  "disabled": ["trufflehog", "dockle"],
  "scope": "codebase",
  "autofix": false
}
```

Only include keys the user explicitly configured. Omitted keys use defaults.

Tell the user: "Configuration saved to `.claude/code-guardian.config.json`. CLI arguments always override these defaults."

## Configuration File Reference

**Location**: `.claude/code-guardian.config.json`

| Key        | Type     | Default        | Description                                           |
|------------|----------|----------------|-------------------------------------------------------|
| `tools`    | string[] | (all available) | Only run these tools. Omit to run all available.     |
| `disabled` | string[] | (none)          | Never run these tools, even if available.            |
| `scope`    | string   | `"codebase"`    | Default scan scope: codebase, uncommitted, unpushed. |
| `autofix`  | boolean  | `false`         | Auto-fix findings by default.                        |

**Precedence**: CLI `--tools` / `--scope` / `--autofix` always override config values.

**`tools` vs `disabled`**: Use `tools` to whitelist (only run these). Use `disabled` to blacklist (run everything except these). If both are set, `tools` takes precedence.

## Important Notes

- This command is read-only by default — it only writes the config file if the user opts in
- Tool availability is cached for 24 hours so future scans skip re-detection
- Scans work fine with partial tool coverage — missing tools just mean fewer checks
- The config file should be committed to the repo so the team shares the same defaults
