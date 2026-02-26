---
name: 'auto-bmad-story-lite'
description: 'Lite BMAD story pipeline: only BMAD slash commands, no orchestration overhead'
---

# Load Configuration

Read `_bmad/bmm/config.yaml` and `_bmad/tea/config.yaml` and set the following variables (resolve `{project-root}` to the actual project root path):

| Variable | Source | Example |
|----------|--------|---------|
| `{{output_folder}}` | bmm `output_folder` | `_bmad-output` |
| `{{planning_artifacts}}` | bmm `planning_artifacts` | `_bmad-output/planning-artifacts` |
| `{{implementation_artifacts}}` | bmm `implementation_artifacts` | `_bmad-output/implementation-artifacts` |
| `{{test_artifacts}}` | tea `test_artifacts` | `_bmad-output/test-artifacts` |
| `{{auto_bmad_artifacts}}` | derived: `{{output_folder}}/auto-bmad-artifacts` | `_bmad-output/auto-bmad-artifacts` |

All paths in this command that reference BMAD output directories MUST use these variables — never hardcode `_bmad-output` paths.

# Detect Story ID

A story ID is composed by exactly 2 numbers: the epic number and the story number within that epic, separated by a dash, a dot, or a space. For example, "1-1" would be the first story in the first epic, "2-3" would be the third story in the second epic, and so on. A story ID can also be inferred from the path name if a path is provided when launching the workflow (e.g., `{{implementation_artifacts}}/1-2-authentication-system.yaml` would set the story ID to "1-2").

**IMPORTANT**: The dash (or dot/space) in a story ID is a SEPARATOR, not a range. `1-7` (or `1.7` or `1 7`) means "epic 1, story 7" — it does NOT mean "stories 1 through 7". This pipeline processes exactly ONE story per run. Never interpret a story ID as a range of stories.

IF user provides epic-story number (e.g. 1-1, 1-2, 2.1, 2.2, etc.) or a file path containing an epic-story pattern:
THEN set {{STORY_ID}} to the provided epic-story number (always a single story).
ELSE ask to provide a epic-story number to identify the story to work on and set {{STORY_ID}} to the provided value.

# Lite Story Pipeline

Run the BMAD story pipeline for story {{STORY_ID}} as a minimal sequence of BMAD slash commands — no orchestration overhead, no reports, no git operations. For testing BMAD workflows.

Each step MUST run in its own **foreground Task tool call** (subagent_type: "general-purpose") so that each agent gets a fresh context window.

**CRITICAL — Tool usage rules:**
- **DO** use the Task tool (foreground, default mode) for each step. It blocks and returns the result.
- **DO NOT** use TeamCreate, SendMessage, TaskOutput, TaskCreate, or TaskList. This is a sequential pipeline, not a team collaboration.
- **DO NOT** launch multiple Task calls simultaneously. Wait for each to return before launching the next.
- **DO NOT** execute any step yourself — always delegate to a Task agent.

**Retry policy:** If a step fails, retry it **once**. If the retry also fails, stop the pipeline and report to the user which step failed and why.

## Story File Path Resolution

After step 1 (Create) succeeds, glob `{{implementation_artifacts}}/{{STORY_ID}}-*.md` to find the story file and set {{STORY_FILE}} to its path. If the story file already existed (step 1 was skipped), set {{STORY_FILE}} the same way. All subsequent steps use {{STORY_FILE}}.

# Pipeline Steps

After each step completes, print a 1-line progress update: `Step N/12: <step-name> — <status>`

## Story Creation & Validation

1. **Story {{STORY_ID}} Create**
   - **Skip if:** a story file for {{STORY_ID}} already exists in `{{implementation_artifacts}}/` (glob for `{{STORY_ID}}-*.md`). Log "Story file already exists" with the file path. Set `{{STORY_FILE}}` to the existing file path.
   - **Task prompt:** `/bmad-bmm-create-story story {{STORY_ID}} yolo`

2. **Story {{STORY_ID}} Validate** *(always runs — never skip)*
   - **Task prompt:** `/bmad-bmm-create-story validate story {{STORY_ID}} yolo — fix all issues, recommendations and optimizations.`

## Test-First

3. **Story {{STORY_ID}} ATDD** *(always runs — never skip)*
   - **Task prompt:** `/bmad-tea-testarch-atdd {{STORY_FILE}} yolo`

## Development

4. **Story {{STORY_ID}} Develop** *(always runs — never skip)*
   - **Task prompt:** `/bmad-bmm-dev-story {{STORY_FILE}} yolo`

## NFR Gate

5. **Story {{STORY_ID}} NFR** *(always runs — never skip)*
   - **Task prompt:** `/bmad-tea-testarch-nfr {{STORY_FILE}} yolo`

## Code Reviews

6. **Story {{STORY_ID}} Code Review #1** *(always runs — never skip)*
   - **Task prompt:** `/bmad-bmm-code-review {{STORY_FILE}} yolo — fix all critical, high, medium and low issues.`

7. **Story {{STORY_ID}} Code Review #2** *(always runs — never skip)*
   - **Task prompt:** `/bmad-bmm-code-review {{STORY_FILE}} yolo — fix all critical, high, medium and low issues.`

8. **Story {{STORY_ID}} Code Review #3** *(always runs — never skip)*
   - **Task prompt:** `/bmad-bmm-code-review {{STORY_FILE}} yolo — fix all critical, high, medium and low issues.`

## E2E Tests

9. **Story {{STORY_ID}} E2E**
   - **Skip if:** the story file's `ui_impact` field is explicitly `false`, or the field is absent and the story's acceptance criteria and tasks clearly involve no user-facing UI changes (coordinator reads `{{STORY_FILE}}` to check). Log "No E2E tests needed — backend-only story".
   - **Task prompt:** `/bmad-bmm-qa-generate-e2e-tests {{STORY_FILE}} yolo`

## Traceability & Test Automation

10. **Story {{STORY_ID}} Trace** *(always runs — never skip)*
    - **Task prompt:** `/bmad-tea-testarch-trace {{STORY_FILE}} yolo`

11. **Story {{STORY_ID}} Test Automate**
    - **Skip if:** step 10 (Trace) did NOT report any uncovered acceptance criteria. Log "All ACs covered — no test automation needed".
    - **Task prompt:** `/bmad-tea-testarch-automate {{STORY_FILE}} yolo`

12. **Story {{STORY_ID}} Test Review** *(always runs — never skip)*
    - **Task prompt:** `/bmad-tea-testarch-test-review {{STORY_FILE}} yolo`

# Done

Print: **Story-lite pipeline complete for {{STORY_ID}}.** Review the story file at `{{STORY_FILE}}` and generated artifacts.
