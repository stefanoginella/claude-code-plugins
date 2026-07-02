# Safeguards catalog

A menu, tiered by how essential each item is. Pick a subset that fits the
project's stage and exposure — don't propose the whole list to a weekend
prototype, and don't leave a public commercial repo on tier 1 alone.

## Tier 1 — Core quality (almost always propose these)

- **Format on commit.** Auto-fix formatting on staged files so style never
  becomes a review conversation. Stack tool in `references/git-hooks.md`.
- **Lint on commit.** Catch obvious bugs and anti-patterns before they land.
- **Type-check.** At minimum in CI (often too slow for every commit);
  offer commit-time for stacks where it's fast enough (`tsc --noEmit` on a
  small package is fine, a large monorepo usually isn't).
- **Test suite runs in CI, and at pre-push if fast enough.** Non-negotiable
  for anything beyond a throwaway script.
- **Patch coverage gate.** New/changed lines need meaningful coverage — not
  a repo-wide coverage percentage, which just pressures people into
  padding unrelated files. Diff-scoped coverage tools per stack are in
  `references/git-hooks.md`.

## Tier 2 — AI-slop-specific

These target failure modes that are disproportionately common in
AI-generated code, not just generic bugs.

- **Mutation testing.** Coverage tells you code *ran*; mutation testing
  tells you the tests actually *assert* something — it injects small
  faults and checks the suite catches them. This directly targets a known
  AI-slop pattern: tests that hit every line but don't fail when the logic
  is wrong. Maturity varies sharply by ecosystem (StrykerJS for
  Node/TS and Infection for PHP are solid; Go's tooling is notably
  weaker) — propose it as a hard gate only where the ecosystem's tooling
  is mature enough; otherwise offer it as an optional/scheduled check
  rather than a blocking one. Keep it out of pre-commit regardless — it's
  slow; run it in CI or nightly.
- **Slopsquatting / dependency-hallucination check.** LLMs reproducibly
  hallucinate plausible-but-nonexistent package names; attackers
  pre-register those names with malicious payloads and wait. This is
  distinct from generic typosquatting — it's specifically about *new*
  dependencies an agent just added. Verify every new dependency actually
  resolves in the registry and has a plausible history (age, download
  count, real maintainer) before it's allowed in. Tools: `slopcheck`
  (purpose-built for this), `guarddog` (PyPI/npm/Go/GitHub Actions,
  name-similarity + malicious-code heuristics), or a general supply-chain
  scanner (Socket, OSV-Scanner) as a broader net.
- **Dead-code / unused-export detection.** AI-assisted edits leave orphaned
  functions and unused exports behind more often than hand-written diffs
  do, since nothing forces a full-repo mental model on every change.
  Stack-appropriate tool (`ts-prune`/`knip` for TS, `vulture` for Python,
  `deadcode`/`unused` linters elsewhere).
- **Assertion-density lint for tests.** A lighter-weight cousin of mutation
  testing — flag test files with suspiciously few assertions relative to
  their length, as a fast pre-commit-friendly signal (mutation testing is
  the CI-time confirmation).

## Tier 3 — Security

- **Secret scanning.** Pre-commit (fast, offline — Gitleaks is the
  established default; note that active development in this space has
  been shifting toward newer tools from the same lineage, so it's worth a
  quick current-tool check at propose time) plus a deeper CI pass
  (TruffleHog, which verifies whether a found credential is still live,
  not just pattern-matched). If the repo is hosted on GitHub, its native
  secret scanning + push protection is a good complementary layer — it
  still catches a leak even if someone bypasses the local hook with
  `--no-verify`.
- **SAST.** Semgrep is the standard cross-language static analysis tool —
  wire the `semgrep` CLI into a hook/CI job directly; an interactive
  Semgrep integration in the editor or agent session is a separate,
  complementary surface, not a substitute for a headless CI check.
- **Dependency / vulnerability audit.** The package manager's own audit
  command as a first pass (`npm audit`, `composer audit`, `pip-audit`),
  layered with a federated-database scanner (OSV-Scanner) for broader
  coverage, since single-registry audits miss cross-ecosystem advisories.
- **Container scanning**, if a `Dockerfile` exists — base-image and layer
  vulnerability scan (Trivy or equivalent) in CI.

## Tier 4 — Supply chain

- **Lockfile enforcement.** CI installs with `--frozen-lockfile` (or the
  stack's equivalent) so a drifted lockfile fails loudly instead of
  silently resolving different versions than what's committed.
- **Pinned CI actions/dependencies.** Third-party GitHub Actions pinned to
  a full commit SHA, not a mutable tag — detailed in `references/ci.md`.
- **Automated dependency updates.** Dependabot or Renovate, so version
  bumps arrive as reviewable PRs instead of accumulating silently.
- **Provenance/attestations**, for a published package — build provenance
  (e.g. npm's or GitHub's attestation support) if the project ships
  artifacts publicly. Higher tier — propose for a community-OSS or
  commercial-product repo, not a personal project.

## Tier 5 — Repo governance

Scale with the classification from `references/stack-detection.md` §6 —
these matter far more for a public/commercial/community repo than a
personal one.

- **`CODEOWNERS`** — require review from the right people on the right
  paths. Needs real names/teams; never fabricate them.
- **Branch protection** (required reviews, required status checks, no
  force-push to main). This needs repo-admin access on the hosting
  platform — codeguard can't set it from the repo's filesystem, so surface
  it as a "your turn" item with the exact settings to enable, not
  something this run finishes unassisted.
- **`SECURITY.md`** with a disclosure process. Only include contact
  details the user explicitly approves — never scrape an email from git
  config into a public file.
- **PR/issue templates** — worth proposing once a repo has more than one
  regular contributor.

## Tier 6 — Frontend-specific

- **Accessibility linting.** `eslint-plugin-jsx-a11y` (React) or
  framework-equivalent, catching missing alt text, bad ARIA usage, and
  unlabeled form controls at commit time — cheap, and accessibility bugs
  are otherwise easy to miss entirely in review.
- **Bundle-size / performance budget.** A Lighthouse CI budget or
  bundler-native size-limit check in CI, so a dependency addition that
  silently doubles the bundle gets caught before merge, not after a user
  complaint.
- **CSP / security headers.** If the project serves HTML directly (not
  just an API), lint for a Content-Security-Policy and standard security
  headers rather than leaving them as an afterthought.
- **Visual regression** — optional/higher tier; propose for a
  design-sensitive commercial product, not by default.

## Tier 7 — Generation-time guardrails (Claude Code-native)

- **`CLAUDE.md` conventions.** The stack's formatting/lint/test commands,
  the testing expectation ("new code ships with meaningful,
  assertion-bearing tests"), and any project-specific patterns to follow
  or avoid. This is the cheapest, highest-leverage safeguard — it steers
  generation instead of just catching output after the fact.
- **Definition-of-Done `Stop` hook.** Blocks the agent from ending its turn
  while lint/type/test checks are red, with bounded retries so it can't
  loop forever. Full mechanics in `references/agent-guardrails.md`. This
  is the one safeguard in the catalog that's Claude-Code-specific rather
  than a general repo practice — flag that plainly when proposing it, so
  the user understands it won't do anything for a contributor using a
  different tool.

## Choosing a subset

A reasonable default shape:
- **Personal / prototype**: tier 1 (format, lint, quick tests) plus secret
  scanning. Skip mutation testing, governance, and most of tier 4.
- **Team-internal product**: tiers 1–4, tier 6 if it's a frontend, DoD hook
  if the team leans on Claude Code heavily.
- **Commercial product or community OSS**: all tiers, with tier 5
  governance items surfaced even where they need the user's hands (branch
  protection, `CODEOWNERS`).

Always let the user's stated priorities override this default — the
classification is a starting point for the proposal, not a rule to enforce
over their judgment.
