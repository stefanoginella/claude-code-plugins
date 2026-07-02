# codeguard

A Claude Code plugin that hardens a repository against AI-generated slop — and
plain old human mistakes — with a tailored set of git hooks, CI pipelines, and
agent-facing coding standards.

## What it does

The `codeguard-setup` skill walks through a repo, works out its stack (even
for a greenfield project that only has docs so far), and proposes a concrete,
approval-gated plan: what to add, what to change, what's already fine as-is.
Once approved, it wires everything up — hook manager, CI jobs, `CLAUDE.md`
conventions, and, if you want it, a Claude Code `Stop` hook that keeps the
agent from ending its turn while checks are red.

It leans on two layers of defense:

1. **Generation time** — coding standards written into `CLAUDE.md` so the
   agent follows the project's conventions before it writes the code.
2. **Commit / CI time** — hooks and pipelines that mechanically catch what
   slips through: formatting, lint, types, tests, secrets, vulnerable or
   hallucinated dependencies, assertion-free tests.

## Install

Add the marketplace and install the plugin:

```
/plugin marketplace add stefanoginella/claude-code-plugins
/plugin install codeguard
```

## Usage

In any repo, just ask:

```
Harden this repo against AI slop
Set up pre-commit hooks and CI for this project
Add safeguards / guardrails to this codebase
```

The skill triggers on intent, not on a specific phrase — see
`skills/codeguard-setup/SKILL.md` for the full workflow and
`skills/codeguard-setup/references/` for the stack-detection signals,
safeguards catalog, and per-mechanism guides it draws on.

## Supported stacks

Canonical, opinionated hook/CI profiles for Node/TypeScript, Python, Go,
Rust, and PHP — see `skills/codeguard-setup/references/git-hooks.md`. Any
other stack is handled too: codeguard web-searches for that ecosystem's
current idiomatic tooling instead of guessing.

## Scope

codeguard raises the floor — it can't judge whether code is *correct* or
solves the right problem, and it doesn't design your test strategy. It's
defense in depth beneath good specs and human review, not a replacement for
either. See the SKILL.md "Scope & limits" section for the full picture.

## License

MIT — see the repository root [LICENSE](../../LICENSE).
