---
name: security-guardian-ci
description: Generate CI security scanning pipeline configuration
argument-hint: "[github-actions|gitlab-ci|auto]"
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Glob
---

# CI Security Pipeline Generator

Generate CI/CD pipeline configuration for security scanning based on the project's detected stack.

## Execution Flow

### Step 1: Detect Stack

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh .
```

### Step 2: Determine CI System

If `$ARGUMENTS` specifies a CI system, use that. Otherwise:

1. Check detected CI systems from stack detection
2. If multiple CI systems detected, ask which one to generate for
3. If none detected, ask the user which CI system they use (offer: GitHub Actions, GitLab CI, other)

### Step 3: Check Existing CI Config

Check if there's already a security scanning configuration:
- GitHub Actions: look for `.github/workflows/security*` or security-related steps in existing workflows
- GitLab CI: look for security stages in `.gitlab-ci.yml`

If security scanning already exists, show what's configured and suggest additions/improvements.

### Step 4: Generate Configuration

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ci-recommend.sh \
  --stack-json /tmp/cg-stack.json \
  --ci-system <system>
```

### Step 5: Present and Write

Present the generated configuration to the user. Ask if they want to:

1. **Write to file**: Create/update the CI config file directly
2. **View only**: Just display it for manual copy
3. **Customize**: Modify before writing (e.g., change triggers, add/remove tools)

If writing to file:
- GitHub Actions: Write to `.github/workflows/security.yml`
- GitLab CI: Append to `.gitlab-ci.yml` or create `.gitlab-ci-security.yml` for include

### Step 6: Additional Recommendations

Based on the stack, recommend:
- Pre-commit hooks for local scanning (gitleaks, semgrep)
- Branch protection rules to require security checks
- Scheduled scans for dependency vulnerabilities (weekly)
- SARIF upload for GitHub Security tab integration

## Important Notes

- Never overwrite existing CI config without confirmation
- If the project already has CI, suggest adding security as a new job/stage rather than a separate workflow (when appropriate)
- Include `allow_failure: true` or `continue-on-error: true` for initial rollout so security doesn't block all PRs
- Always include secret detection (gitleaks) as a baseline
