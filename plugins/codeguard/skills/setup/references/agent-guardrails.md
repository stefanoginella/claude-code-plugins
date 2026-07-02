# Agent guardrails (Claude Code-native)

Two mechanisms, both specific to Claude Code rather than general repo
practice — say so plainly when proposing either, so the user understands
neither does anything for a contributor using a different tool.

## CLAUDE.md conventions

Write the stack's commands and expectations into `CLAUDE.md` — format/lint/
type/test commands, the testing expectation, and any project-specific
pattern worth stating. If `CLAUDE.md` already has real content, don't
touch the user's prose; write only inside a sentinel block, appended if
there's existing content, whole-file if not:

```markdown
<!-- codeguard:start -->
## Code quality

- Format: `<command>`
- Lint: `<command>`
- Type-check: `<command>`
- Test: `<command>`

New code ships with meaningful, assertion-bearing tests — not just tests
that execute the code path.
<!-- codeguard:end -->
```

On every run, look for this block **first**. If it's there, rewrite its
contents in place rather than appending a second copy. Never edit outside
the sentinels — that's the user's space, and a re-run that mangles their
own notes will make them stop trusting the tool.

Check whether `CLAUDE.md` is a **symlink** before writing — commonly to
`AGENTS.md` in repos meant to serve multiple agent tools. Writing "to
`CLAUDE.md`" in that case silently edits whatever it points to, which
other tools may read too. Flag this and get an explicit OK first.

## Definition-of-Done `Stop` hook

Blocks Claude Code from ending its turn while the project's checks are
red, nudging it to actually fix what it broke instead of handing back
broken work. It's advisory, not a hard gate — pre-push hooks and CI are
the hard gates; this just catches things one step earlier, mid-session.

### Wiring

Add to `.claude/settings.json` (team-shared, meant to be committed) or
`.claude/settings.local.json` (personal-only, conventionally gitignored —
ask which the user wants; default to the shared file unless they want this
opt-in per-developer):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/dod-check.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

`Stop` fires whenever Claude finishes responding — no `matcher` is needed
(matchers scope to specific tool names on events like `PreToolUse`; `Stop`
isn't tool-scoped). Settings-file hook edits are picked up automatically
by Claude Code's file watcher — no restart needed mid-session.

**Re-run rule**: identify codeguard's own entry by its script path
(`.claude/hooks/dod-check.sh`), and merge into the `Stop` array rather than
overwriting it — another hook may already be registered there. Never touch
an entry that isn't codeguard's.

**Don't let `.claude/` end up gitignored.** If it is, the committed
`settings.json` and the hook script under it never reach a fresh clone or
CI runner — check this explicitly as part of setup, not just at inventory
time.

**Do gitignore the state file.** The hook script tracks its retry count in
`.claude/.dod-attempts` — mutable, per-session state that has no business
in version control and would otherwise dirty `git status` after every
session. Add a `.claude/.dod-attempts` line to `.gitignore` as part of
setup (the rest of `.claude/` stays tracked).

### The input/output contract

The hook script receives a JSON object on stdin with (at least)
`session_id`, `transcript_path`, `cwd`, `permission_mode`, and
`hook_event_name`. It talks back to Claude Code one of three ways:

- **Exit code `2`** — blocking. Claude Code reads stderr as the reason and
  continues instead of stopping. Simplest option, good for a plain
  pass/fail check script.
- **Exit `0` + JSON on stdout**, `{"decision": "block", "reason": "..."}` —
  structurally equivalent to exit 2, useful when the script wants to emit
  other JSON fields alongside.
- **`hookSpecificOutput: {"hookEventName": "Stop", "additionalContext": "..."}`**
  — non-blocking: surfaces information without preventing the stop. Use
  this for the final, "giving up" message described below.
- **`continue: false` + `stopReason`** — forces a hard stop even if
  something else in the flow would otherwise continue. Not needed for a
  DoD check; noted here so it isn't confused with `decision: block`.

These are the fields the current hooks documentation actually specifies —
don't invent additional ones (e.g. a `systemMessage` field with bespoke
semantics), and re-verify against the live docs at propose time, since
this surface has changed before.

### There is no built-in loop cap — the script must bound itself

Nothing in Claude Code caps how many times a `Stop` hook can block in a
row. Left unbounded, a check that can't actually be fixed (a flaky test, a
misconfigured linter) would trap the session in an infinite retry loop.

The shipped template at **`assets/dod-check.sh`** (relative to this
skill's directory) handles this with a per-session attempt counter. To
install it:

1. Copy it to `.claude/hooks/dod-check.sh` in the target repo.
2. Fill in the placeholders: `<plugin-version>` in the provenance marker
   (from this plugin's `plugin.json`), and the stack's actual
   `<lint command>`, `<type-check command>`, `<test command>` — inlined
   in the `if` condition, exactly where the placeholders sit. Don't
   refactor them into a helper function: older bash (macOS's stock
   `/bin/bash` is still 3.2 for licensing reasons) doesn't reliably
   suspend errexit semantics for a function called as an `if`/`while`
   condition, and the script must not depend on that. If the stack has no
   type checker, drop that placeholder rather than leaving it behind.
3. `chmod +x .claude/hooks/dod-check.sh`.
4. Add `.claude/.dod-attempts` to `.gitignore` (see the wiring section
   above).

Properties the template guarantees — keep them intact if you adapt it
further:

- **Bounded.** It gives up blocking after `MAX_ATTEMPTS` (default 3) and
  releases with a non-blocking `additionalContext` message — the whole
  point is a nudge, not a hostage situation.
- **Keyed by `session_id`**, so parallel or separate sessions don't share
  a counter — and it cleans up its own state entry on success.
- **No hard `jq` dependency.** It prefers `jq` for parsing the hook
  payload but falls back to a `sed` extraction when `jq` is absent — a
  missing tool must never turn a Stop hook into an error on every turn,
  and inside a container (see `references/devcontainers.md`) installing
  `jq` at runtime may not even be possible.
- **No `set -e`** — deliberately. The script's job is to inspect failing
  exit codes, and errexit fights that; the template's header comment
  explains it in full. `-u` and `pipefail` stay on.
- **Never assumes the state file exists.**

### Verifying it without trapping yourself

Test the script directly with a synthetic stdin payload
(`echo '{"session_id":"test",...}' | .claude/hooks/dod-check.sh`) rather
than actually ending a real turn against broken code — that would trigger
the exact loop the bounded-retry logic exists to prevent, on your own
setup session.

### What to tell the user

State plainly, at wrap-up: the hook releases after its bounded retries and
stays advisory from then on — it's a nudge mid-session, not a substitute
for pre-push and CI, which remain the actual hard gates.
