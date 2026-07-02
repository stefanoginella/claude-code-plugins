---
name: codeguard-setup
description: >-
  Detects a repository's tech stack (or infers it from docs/specs for a
  greenfield project) and sets up a tailored set of quality & security
  safeguards — git hooks, CI pipelines, secret/SAST/dependency scanning,
  slopsquatting checks, and coding standards baked into CLAUDE.md — to
  prevent AI-generated slop and keep code correct, secure, and maintainable.
  Use this whenever the user wants to harden a repo, prevent "AI slop" or
  "vibe coding" drift, enforce code quality / coding standards / best
  practices, add or review pre-commit hooks or CI checks, wire up
  linting / formatting / type-checking gates, add secret or vulnerability
  scanning, set up mutation testing, or "guard" / "lock down" / "add
  safeguards to" a codebase — even if they never say the word "codeguard".
  Also reach for this on a greenfield repo that only has docs or specs so
  far, to get guardrails in place before real coding begins.
---

# codeguard-setup

Set up the **safeguards** that keep a repository's code — whether written by
a human or an AI agent — correct, secure, and maintainable. The deliverable
is a working setup, not a report: git hooks, CI pipelines, scanners, and
agent-facing coding standards, chosen for this project's actual stack and
built on top of whatever already exists rather than around it.

This is an **interactive, approval-driven** workflow — it edits the user's
repository (hooks, CI config, lint configs, `CLAUDE.md`), so move
deliberately: detect → confirm → propose → get approval → set up → verify.
Never write or overwrite a file before the plan covering it has been
approved.

**If the user has clearly waived the gates** ("use your defaults, don't
ask", "just set it up") — not mere enthusiasm ("harden this repo!") — you
can collapse the confirmation stops: do every step, but narrate the detected
stack and the plan as you go instead of pausing for sign-off. Keep the
stops, though, for anything genuinely ambiguous or hard to undo: an unclear
stack, an unclear repo classification, writing through a symlinked
`CLAUDE.md`, publishing contact details, anything outward-facing. If you're
not sure the user meant to waive a gate, keep it — asking is the default,
and cheap; redoing a wrong setup is not.

## Why two layers

Slop is best fought at two points, and a good setup uses both:

1. **Generation time** — conventions written into `CLAUDE.md`, so the agent
   follows the project's standards *before* it writes the code. This
   prevents slop instead of merely catching it after the fact.
2. **Commit / CI time** — hooks and pipelines that mechanically catch what
   generation-time guidance misses: bad formatting, type errors, leaked
   secrets, vulnerable or hallucinated dependencies, tests that run but
   don't actually assert anything.

The catalog in `references/safeguards-catalog.md` is a menu, not a
checklist — the right selection depends on the project's stack, its stage,
and how exposed it is. Don't put a production service's checklist on a
weekend prototype, and don't leave a public commercial repo under-protected.

## Workflow

### 1. Orient, detect stack, and detect environment

Do all three together — the environment read shapes what's even possible to
install later, so it needs to happen up front, not as an afterthought.

- Confirm you're in a git repository (`git rev-parse --is-inside-work-tree`).
  If not, offer to `git init` — most safeguards need it, hooks especially.
- Tell the user, in one line, what you're about to do: detect the stack,
  see what's already in place, and come back with a tailored plan.
- **Detect the stack.** Read `references/stack-detection.md` for the full
  signal table — manifests, lockfiles, file extensions, build tooling,
  monorepo markers. If the repo is **greenfield** (little or no code yet),
  infer the *intended* stack from its markdown docs — `CLAUDE.md`,
  `AGENTS.md`, `README.md`, `ARCHITECTURE.md`, and spec/plan directories
  such as `docs/`, `specs/`, `plans/`, `adr/`, or method-specific output
  like `_bmad-output/` — see the reference for the full path list.
- **Still can't tell?** Ask the user directly, or ask what to read. Don't
  guess silently — a wrong stack guess poisons every step after it.
- **Detect the runtime environment** — host machine, generic devcontainer,
  or **aicontainer** — per `references/devcontainers.md`. This matters now,
  not later: inside aicontainer, runtime `sudo apt` is blocked outright; in
  a generic devcontainer a runtime install works but silently disappears on
  the next rebuild. Either way, a safeguard that needs a *system* package
  has to be routed to a Dockerfile + rebuild instead of installed live, so
  knowing this before you propose anything keeps the plan honest.
- **Classify the repo** on two axes — visibility (public/private) and
  purpose (personal / team / commercial product / community OSS) — per
  `references/stack-detection.md` §6. This drives how strict the governance
  tier should be. Ask if the signals are ambiguous, and never add anyone's
  contact details to a generated file without their explicit go-ahead.
- **Present the detected stack, environment, and classification, and ask
  for confirmation** before moving on. Let the user correct you. (In a
  waived-gates run, present this as a short report and continue.)

### 2. Inventory what already exists

Before proposing anything, find out what's already there and form an
opinion on it — partial coverage should usually be extended, not replaced.
Check for existing git hooks, CI/CD config, linter/formatter/type-check
config, security/supply-chain tooling, governance files, and any existing
`CLAUDE.md` — the checklist is in `references/stack-detection.md`.

For each thing you find, decide: solid, partial, or misconfigured? What's
missing? This becomes the add / change / leave-as-is split in the proposal.

### 3. Build the proposal

Read `references/safeguards-catalog.md` and pick a tailored subset for this
repo. Then work out the mechanics:

- **Git hook manager** — read `references/git-hooks.md` for the canonical
  per-stack profiles (Node/TS, Python, Go, Rust, PHP). For a stack that
  isn't covered there, **web-search the current idiomatic tooling** for
  that ecosystem instead of guessing or reaching for a stale default — this
  space moves fast enough that hardcoded advice goes stale within a year.
- **CI provider** — default to **GitHub Actions**; if the repo already runs
  a different CI, evaluate and extend that instead (ask if there's a
  preference). See `references/ci.md`, which bakes in the security
  hardening that should always be present: pinned actions, least-privilege
  `permissions`, no long-lived cloud credentials where OIDC will do.

Present the plan so it can actually be judged:

- **What** changes, by exact path, grouped as add / change / leave-as-is.
- **Why** each safeguard is there — tie it to quality, security,
  maintainability, or a specific slop pattern. One line each; if you can't
  justify a check that tightly, drop it from the proposal.
- **Cost** — new dependencies, added commit friction, anything that needs
  the user's hands outside the repo (CI secrets, branch-protection settings
  that need admin rights, a container rebuild). If step 1 found a
  container, say up front which safeguards are host-side work, not
  something this run can finish alone.

Keep commit-time checks fast (staged files only) and push slower, more
thorough checks to pre-push and CI — say so explicitly in the plan so the
tradeoff is visible.

**If the inventory turns up nothing worth adding or changing**, say so
plainly instead of manufacturing work: show what's already solid and stop.
A re-run that finds nothing to improve is success, not a shortfall — that's
what makes this skill safe to run more than once on the same repo.

### 4. Approve, iterate, or refuse

A real decision gate — don't skip it, and don't soften it into a formality.
(In a waived-gates run this is already answered; deliver the plan as a
report and continue to setup.)

- **Refuse** → stop cleanly, make no changes, thank them. Valid outcome.
- **Iterate** → ask specifically what's wrong (too strict? wrong tool? too
  slow? missing something?), revise, re-present. Repeat until approved or
  refused.
- **Approve** → move to setup.

### 5. Set up

Only write files now, exactly as approved.

- **Mark provenance.** In every file codeguard creates, where the syntax
  allows a comment, put one line at the top:
  `# generated by codeguard v<plugin-version> — delete this line to take ownership`
  (version from this plugin's `plugin.json`; drop the version if you can't
  read it). On a re-run, a marker-bearing file is codeguard's to rewrite in
  place; a file without one — including one whose marker the user stripped
  — is the user's, so extend it instead of replacing it.
  (`CLAUDE.md` uses the sentinel block below instead; the Stop-hook entry in
  `settings.json` is identified by its script path.) The marker also makes
  undo mechanical later. It's easy to remember for a hand-written script
  and easy to forget for a YAML/config file assembled from a template in
  your head — so before moving on, re-list every file you just created and
  confirm each one that can take a comment actually has the line, rather
  than trusting you added it everywhere as you went.
- Install and activate the hook manager (`lefthook install`,
  `pre-commit install`, `npm run prepare` / husky, `captainhook install`,
  whichever fits) so hooks actually fire, and `chmod +x` any native hook
  scripts. If step 1 flagged a container, don't try a runtime `sudo apt`
  here — route system packages to the host per step 6, and install only
  what the sandbox actually permits (language-package-manager tooling, hook
  wiring).
- If AI/agent guardrails were approved, write the stack's conventions into
  `CLAUDE.md` (Claude Code's project-instructions file), creating it if
  missing. If it already has real content, leave the user's prose alone and
  write only inside stable sentinels: `<!-- codeguard:start -->` …
  `<!-- codeguard:end -->`. **Look for that block on every run** — if it's
  already there (e.g. from a previous run), rewrite its contents in place
  rather than appending a second, near-duplicate section. Never touch
  anything outside the sentinels. Also check whether `CLAUDE.md` is a
  **symlink** — commonly to `AGENTS.md` in repos that serve multiple
  agents — since writing "to `CLAUDE.md`" would then silently edit
  whatever it points to; flag this and get an explicit OK before writing
  through it. This is a Claude Code plugin, so `CLAUDE.md` is the only
  agent-instruction file it manages; don't create or rewrite others.
- If a **Definition-of-Done Stop hook** was approved, wire it per
  `references/agent-guardrails.md` — which covers the `settings.json` vs
  `settings.local.json` choice, the re-run rule (find codeguard's entry by
  its script path, merge rather than overwrite, never touch other hooks),
  making sure `.claude/` isn't gitignored, and how to verify the hook
  without tripping it on yourself mid-setup.
- **Verify without mutating the user's tree**: check every file you created
  for the provenance marker (`grep -rL "generated by codeguard" <the files
  you just wrote>` — anything listed is missing it and needs the line
  added), lint the CI YAML (`actionlint`, see `references/ci.md`), and
  confirm hooks are wired using
  each manager's dry-run / check-only mode (`references/git-hooks.md`;
  inside a container, the sandbox-safe variant in
  `references/devcontainers.md`). **Scope checks to code the project
  actually owns** — if the repo vendors tooling or generated output
  (`_bmad-output/`, `.automator/`, build dirs), exclude it so the gate
  isn't red on code nobody's going to touch. If truly confirming a hook
  fires would require running an auto-fixer against real files, say so
  before doing it.
- Don't auto-commit unless asked. Stage the changes and show a summary; the
  commit stays the user's call. If a hook needs its own config committed to
  work at all (e.g. a `.pre-commit-config.yaml`), say so.

### 6. Act on the environment

Step 1 already detected host vs. devcontainer vs. aicontainer — now act on
it, because it changes what the user has to do **outside this session**.
Re-read `references/devcontainers.md` for the exact playbook.

- **aicontainer**: state the host-side requirements precisely. Runtime
  `sudo apt` is blocked, so any safeguard needing a system package goes
  into `.devcontainer/Dockerfile.project`, and hook installation belongs in
  `.devcontainer/post-create.project.sh` so it survives a rebuild. Give the
  exact snippet to add and say plainly that a rebuild is required.
- **Generic devcontainer**: warn that a runtime install may not survive a
  rebuild, and point to the Dockerfile / post-create script as the durable
  place for it.
- **Not in a container**: note that CI runs in a clean environment, so
  every tool version should be pinned and every dependency declared —
  nothing installed "by hand" during this session will be there in CI.

### 7. Wrap up

**Reconcile against the plan first.** Diff what actually got written
against what was approved: every promised safeguard should be present in
the files (a SAST or dependency-audit job that silently didn't make it into
the CI YAML is a real gap, not a rounding error), and every doc reference
should point at something that exists (don't describe a
`Dockerfile.project` you didn't create).

Then summarize plainly: what's set up, how to run each check by hand, how
to bypass a hook in an emergency (`git commit --no-verify`) and why that
should stay rare, and a short **"your turn"** list — CI secrets/tokens,
branch-protection settings that need repo-admin, a container rebuild, a
first `pre-commit run --all-files` to baseline the repo. If the DoD Stop
hook went in, say plainly that it releases after its bounded retries and
stays advisory until a green pass — it's a nudge mid-session, not the hard
gate; pre-push and CI are that.

Explain how to **undo** codeguard later: delete the
`<!-- codeguard:start -->` … `<!-- codeguard:end -->` block in `CLAUDE.md`,
remove the DoD entry from `.claude/settings.json` (or
`.claude/settings.local.json`) along with its script, and drop the
generated hook/CI/config files — `git grep -l "generated by codeguard"`
lists every marker-bearing file, so removal doesn't rely on memory.

## Reference files

Load these as needed, not all at once:

- `references/stack-detection.md` — signals for detecting the stack
  (including greenfield-from-docs) and the existing-safeguards inventory
  checklist.
- `references/safeguards-catalog.md` — the full tiered catalog to choose
  from: core quality, security, AI-slop-specific, supply-chain, repo
  governance, frontend, generation-time guardrails.
- `references/git-hooks.md` — hook-manager decision guidance, the canonical
  per-stack profile table, and install/verify commands per manager.
- `references/ci.md` — GitHub Actions templates, security hardening, and
  notes for adapting to other providers.
- `references/agent-guardrails.md` — the Definition-of-Done `Stop` hook:
  exact settings.json wiring, the input/output contract, and why it needs
  its own bounded-retry logic.
- `references/devcontainers.md` — detecting host / devcontainer /
  aicontainer, and exactly what each implies for where a safeguard's
  install step belongs.

## Scope & limits

Be straight with the user about what this buys them and what it doesn't.

- **Safeguards raise the floor, not the ceiling.** These gates catch known
  failure modes — bad formatting, type errors, leaked secrets, vulnerable
  or hallucinated dependencies, tests that run without asserting anything.
  They can't judge whether the code is *correct*, well-designed, or solving
  the right problem. Every check can stay green on a wrong spec. codeguard
  is defense in depth beneath good specs and human review — never a
  substitute for either.
- **It enforces testing, it doesn't design the test strategy.** In scope:
  the *gates* — the suite runs at commit/push/CI, new code clears a
  patch-coverage bar, mutation testing (where the ecosystem's tooling is
  mature enough) confirms tests actually assert something. Also in scope:
  writing a testing *expectation* into `CLAUDE.md`. Out of scope: the
  unit/integration/e2e mix, what deserves coverage, TDD or not — that's a
  project-design call, not something to impose from a setup script.
- **POSIX assumed.** Hook scripts target a POSIX shell (macOS, Linux, WSL,
  devcontainers). On a native-Windows repo, say so and adapt (PowerShell
  hooks, or point at WSL) instead of handing over bash that won't run.

## Principles

- **Tailor, don't dump.** The catalog is a menu. Match the protection to
  the project's stage and its actual exposure — a prototype and a public
  commercial repo don't get the same list.
- **Opinionated on tools, tailored on scope.** *Which* tool for a given
  stack has a current best answer — anchor to the canonical per-stack
  profiles in `references/git-hooks.md` so equivalent repos converge
  instead of drifting apart. A working setup already in the repo wins over
  the canonical default — extend it, don't replace it. Save the tailoring
  for *how much*: which tiers, how strict, driven by the project's stage
  and audience. Present the opinionated default at the approval gate and
  let the user dial it — opinionated isn't the same as rigid.
- **Explain the why.** Every proposed safeguard gets a reason the user can
  actually evaluate. Can't justify it in a line? Don't propose it.
- **Fast feedback first.** Commit-time checks stay quick — staged files
  only. Slow or thorough checks belong at pre-push and in CI.
- **Install pinned and reproducible.** Prefer project-scoped,
  manifest-declared installs (Node devDependencies, a Python dev
  dependency group, a `go.mod` tool directive) over anything system- or
  user-global, so a fresh clone and CI resolve the exact same tool
  versions. Where the ecosystem's idiom is a pinned toolchain-level or
  container-baked install instead (rustup components, a pinned `go
  install`), that's fine — the bar is "pinned and reproducible," not
  "always inside the manifest." Avoid unpinned global installs (bare `brew
  install`, `npm i -g`) that drift machine to machine.
- **Never surprise the user.** No changes before approval, no
  auto-commits, always flag anything that needs work outside the repo.
- **Stay current.** Tooling in this space moves fast — where you're not
  sure a recommendation is still the idiomatic one, web-search rather than
  trust memory that might be a year stale.
