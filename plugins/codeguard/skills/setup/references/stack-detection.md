# Stack detection

## 1. Manifest & lockfile signals

Check for these first — they're the strongest, least ambiguous signal.

| File | Stack | Package manager tell |
|---|---|---|
| `package.json` | Node/TypeScript | `package-lock.json` = npm, `pnpm-lock.yaml` = pnpm, `yarn.lock` = yarn, `bun.lock(b)` = bun |
| `pyproject.toml`, `requirements*.txt`, `Pipfile` | Python | `uv.lock` = uv, `poetry.lock` = Poetry, `Pipfile.lock` = pipenv, bare `requirements.txt` = pip |
| `go.mod` | Go | `go.sum` present alongside |
| `Cargo.toml` | Rust | `Cargo.lock` |
| `composer.json` | PHP | `composer.lock` |
| `Gemfile` | Ruby | `Gemfile.lock` |
| `pom.xml` / `build.gradle(.kts)` | Java/Kotlin | Maven vs Gradle |
| `*.csproj` / `*.sln` | .NET | — |

A repo can legitimately have more than one (a Node frontend + Python
backend, a Go service with a Rust CLI tool) — detect and report *all* of
them, don't collapse to one.

## 2. Framework & build-tool signals

Once the language is known, narrow the framework from what's actually
imported/configured, not just what's installed:

- **Frontend**: `next.config.*` (Next.js), `astro.config.*` (Astro),
  `vite.config.*` + a UI framework dependency (React/Vue/Svelte via Vite),
  `angular.json`, `svelte.config.js`, `nuxt.config.*`.
- **Backend**: `manage.py` (Django), a `fastapi`/`flask` import at the
  entrypoint, `spring-boot-starter` in a Gradle/Maven file, a `rails`
  Gemfile entry, `express`/`fastify`/`hono` in `package.json` deps.
- **Monorepo tooling**: `turbo.json` (Turborepo), `nx.json` (Nx),
  `pnpm-workspace.yaml`, a Cargo/Go workspace block, `lerna.json`. This
  changes where hook/CI config should scope to (per-package vs. root) —
  flag it in the proposal rather than defaulting to root-only.

## 3. Greenfield: infer from docs

Little or no code yet? Read markdown before asking the user cold. Check, in
rough priority order:

1. `CLAUDE.md`, `AGENTS.md` — agent-instruction files often state the stack
   outright ("This is a Next.js + tRPC + Postgres project...").
2. `README.md` — badges, a "Tech Stack" / "Getting Started" section.
3. `ARCHITECTURE.md`, `DESIGN.md`, `TECH_STACK.md`, `docs/adr/` (Architecture
   Decision Records).
4. Spec/plan directories from AI-assisted planning workflows:
   `docs/`, `specs/`, `plans/`, `.specify/`, `_bmad-output/` (BMAD method),
   `.cursor/rules/`, `.windsurf/`. Skim for framework names, language
   choices, and package manager preferences stated in the plan.
5. `.devcontainer/devcontainer.json` or a `Dockerfile` — a base image often
   names the runtime even before any application code exists.

If none of this resolves it, **ask** — name what you checked and ask the
user to state the stack or point at the right doc. Don't guess silently;
a wrong guess here poisons the entire downstream proposal.

## 4. Existing-safeguards inventory checklist

Look for all of these before proposing anything — the goal is
add/change/remove/leave-as-is, not a blind rebuild. Check both
directions: gaps the current stack leaves uncovered, and stale
safeguards aimed at a stack component that's since been removed:

**Git hooks**
- `.husky/`, `lefthook.yml`/`lefthook.yaml`, `.pre-commit-config.yaml`,
  `.git/hooks/*` (native, not manager-driven — note if these are
  hand-rolled and un-versioned, since `.git/hooks` isn't tracked by git),
  `captainhook.json`, `grumphp.yml`.

**CI/CD**
- `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`,
  `Jenkinsfile`, `azure-pipelines.yml`, `.drone.yml`. Read what jobs
  already run, not just that a file exists — a workflow that only deploys
  and never lints is a gap, not coverage.

**Linter / formatter / type-check config**
- `.eslintrc*`/`eslint.config.*`, `.prettierrc*`, `biome.json`,
  `pyproject.toml` `[tool.ruff]`/`[tool.mypy]`, `.golangci.yml`,
  `rustfmt.toml`/`clippy.toml`, `phpstan.neon`, `.php-cs-fixer.php`,
  `tsconfig.json` strictness flags.

**Security / supply-chain**
- `.gitleaks.toml`, `.trufflehog.yml`, `.semgrep.yml`/`.semgrepignore`,
  `dependabot.yml`, `renovate.json`, `.snyk`, a Socket/OSV config, an
  existing `SECURITY.md`.

**Governance**
- `CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`, PR/issue templates in
  `.github/`. (Branch protection itself isn't a file — you can't inspect
  it directly; ask, or note it as a "your turn" item since it needs
  repo-admin access on the hosting platform.)

**Agent instructions**
- `CLAUDE.md` (check if it's a **symlink**, commonly to `AGENTS.md`),
  `.claude/settings.json` / `.claude/settings.local.json` (existing hooks —
  read before touching, so a codeguard addition merges instead of
  clobbering something the user already relies on).

## 5. Environment detection

Covered in full in `references/devcontainers.md` — but do this in the same
pass as stack detection, not later, since it constrains what setup can
actually install live vs. what has to route to a Dockerfile + rebuild.

## 6. Repo classification

Two independent axes; both drive how strict the governance tier should be.

**Visibility** — public or private:
- `git remote -v` plus a check of the hosting platform (a public GitHub
  repo is visible without auth). If uncertain, ask rather than guess —
  getting this wrong risks either under-protecting a public repo or
  over-asking a private one.

**Purpose / stakes** — personal, team-internal, commercial product, or
community open-source:
- Signals: a `LICENSE` file and its type (permissive OSS vs. none vs.
  proprietary), a populated `CONTRIBUTING.md` (suggests external
  contributors are expected), CI badges advertising status to the public,
  package registry metadata (`package.json` `"private": true` is a strong
  "not shipped" signal), how many people show up in recent commit history,
  and simply what the user has told you about the project.

Note the **contributor count** while classifying (recent commit history
is the signal above) — it gates the tier-5 review-enforcement items
independently of purpose, per `references/safeguards-catalog.md`.

When the signals conflict or are thin, **ask** rather than assume the
higher- or lower-stakes reading. And regardless of tier: **never write
anyone's contact details** (an email in `SECURITY.md`, a name in
`CODEOWNERS`) into a generated file without their explicit opt-in —
`SECURITY.md` defaults to a contact-free reporting channel with no email
at all, and an address appears only when the user chooses one. Silently
populating anything from git config is never OK.
