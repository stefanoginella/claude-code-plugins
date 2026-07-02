# Git hooks

## Picking a hook manager

- **Polyglot repo, or no strong existing convention**: default to
  **Lefthook**. It's a single dependency-free Go binary (no Node/Python
  runtime needed just to run hooks), configures every language from one
  `lefthook.yml`, and runs checks in parallel.
- **Pure Python repo**: the **pre-commit** framework is the more idiomatic
  choice there — its hook registry has ready-made entries for ruff/mypy/etc.,
  and it's what most Python maintainers already expect. Prefer Lefthook
  instead only if the repo is genuinely polyglot.
- **Simple, single-language Node project**: husky + lint-staged is a
  reasonable, low-friction choice — `"prepare": "husky"` in `package.json`
  installs hooks automatically on `npm install` with zero extra wiring.
  Lefthook is still the better pick for a monorepo or a project that'll
  likely grow another language.
- **PHP**: **CaptainHook** is PHP-native (JSON config, no YAML-plus-PHP-class
  split) and integrates cleanly with Composer scripts; fall back to Lefthook
  in a polyglot PHP + something-else repo.
- **An existing manager already works**: extend it. Don't migrate a working
  setup to match this list just for consistency — that's real churn for no
  safety gain.
- **Unlisted or unusual stack**: web-search the current idiomatic hook
  manager and lint/format/test tooling for that ecosystem rather than
  guessing or defaulting to Lefthook by default-of-default. Ecosystem
  conventions shift, and a stale hardcoded answer is worse than a quick
  search.

Whatever the manager, scope commit-time checks to **staged files only** —
every option below supports this natively (Lefthook's `{staged_files}`
glob, pre-commit's per-hook `files`/`types` filters, lint-staged for
husky). Push the full-repo / slow checks to pre-push and CI.

## Canonical per-stack profiles

Treat these as the default starting point for a repo with no strong
existing convention — not a mandate to rip out something that already
works.

### Node / TypeScript

| Concern | Tool | Notes |
|---|---|---|
| Format + lint | **Biome** (new/greenfield) or existing ESLint+Prettier (extend, don't migrate) | Biome covers most common ESLint rules at a fraction of the runtime cost; an existing ESLint setup with framework-specific plugins or full type-aware linting is usually not worth migrating off. |
| Type-check | `tsc --noEmit` | Commit-time if the package is small/fast; otherwise pre-push or CI only. |
| Test + coverage | **Vitest** (new projects); **Jest** if already in place, or on React Native, which only supports Jest | Diff-scoped coverage via the runner's built-in coverage + a patch-coverage CI step. |
| Mutation testing | **StrykerJS** | CI/scheduled, not commit-time. |
| Package manager | **pnpm** (new projects); keep npm/yarn if already the convention | `pnpm audit` for the dependency-audit tier. |
| Hook manager | Lefthook (default) or Husky + lint-staged (simple single-language repos) | See decision guidance above. |
| Install | `pnpm add -D lefthook && pnpm lefthook install` | Add `"prepare": "lefthook install"` so a fresh clone wires hooks automatically. |
| Dry-run / verify | `lefthook run pre-commit --all-files` (no `--no-verify` needed; doesn't mutate unless a step does) | Confirms every configured step actually runs. |

### Python

| Concern | Tool | Notes |
|---|---|---|
| Format + lint | **ruff** (`ruff check --fix` + `ruff format`) | Consolidated replacement for flake8/black/isort — don't propose the older trio separately if ruff can cover it. |
| Type-check | **mypy** (safe default) | Faster newer entrants (Astral's `ty`, Meta's `pyrefly`) exist and are worth mentioning as an option, but flag them as newer/less spec-complete rather than defaulting to them silently. |
| Package manager | **uv** | Now the mainstream default over pip/Poetry/pipenv — one tool for deps, venv, and Python version; commit `uv.lock`. |
| Test + coverage | pytest + coverage.py | `diff-cover` (or equivalent) for patch-coverage gating in CI. |
| Mutation testing | **mutmut** | CI-only, not commit-time — it's slow. |
| Dependency audit | **pip-audit** | Checks the lockfile against OSV/PyPI advisories. |
| SAST | **bandit** (Python-specific quick scan) or Semgrep if the repo already uses it / is polyglot | |
| Hook manager | **pre-commit** framework (default for pure-Python) or Lefthook (polyglot) | |
| Install | `uv tool install pre-commit && pre-commit install` | |
| Dry-run / verify | `pre-commit run --all-files` | First run baselines the whole repo — warn that it may touch many files via auto-fixers; confirm before running unattended. |

### Go

| Concern | Tool | Notes |
|---|---|---|
| Lint | **golangci-lint** (v2 config: `version: "2"` at the top of `.golangci.yml`) | Bundles govet, staticcheck, errcheck, revive, etc. |
| Format | **gofumpt** | Stricter superset of `gofmt`; output still passes plain `gofmt`/`goimports` checks, so it's a safe upgrade. |
| Vulnerability scan | **govulncheck** | Official Go team tool; call-graph aware, so fewer false positives than a naive dependency scan — CI standard. |
| Test + coverage | `go test -cover` | No dominant patch-coverage tool for Go; script a diff-scoped filter over `go test -coverprofile` if patch coverage is wanted. |
| Mutation testing | Optional/lower tier — tooling here (`go-gremlins/gremlins`, `sivchari/gomu`) is meaningfully less mature than the JS/PHP equivalents. Propose it opt-in, not as a default gate. | |
| Hook manager | **Lefthook** | Written in Go itself, single binary, no extra runtime — the natural fit. |
| Install | `go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest` (pin a version in CI, not `@latest`) | |
| Dry-run / verify | `lefthook run pre-commit --all-files` | |

### Rust

| Concern | Tool | Notes |
|---|---|---|
| Lint | **clippy** (`rustup component add clippy`) | |
| Format | **rustfmt** (`rustup component add rustfmt`) | |
| Test + coverage | `cargo test` + **cargo-llvm-cov** | Prefer over cargo-tarpaulin for new setups — LLVM source-based instrumentation, cross-platform (tarpaulin is Linux/x86_64-only). |
| Mutation testing | **cargo-mutants** | Zero-config and actively maintained, but still an emerging tool in its adoption curve — propose as opt-in rather than a hard default gate. |
| Security/supply-chain | **cargo-audit** first (RustSec advisories, zero-config); add **cargo-deny** once the team wants license/policy enforcement on top | Layer, don't choose one over the other. |
| Hook manager | **Lefthook** | No Rust-specific manager has real traction; `cargo-husky` exists but is less actively used. |
| Install | `cargo install cargo-audit cargo-llvm-cov` (pin versions in CI) | |
| Dry-run / verify | `lefthook run pre-commit --all-files` | |

### PHP

| Concern | Tool | Notes |
|---|---|---|
| Static analysis | **PHPStan** (default); **Psalm** as an add-on where taint-tracking security analysis (SQLi/XSS/command-injection) is wanted | Not an either/or if the repo is security-sensitive — Psalm's security plugin covers a class of bugs PHPStan doesn't target. |
| Format | **PHP-CS-Fixer** | Auto-fixes what it reports; no unified format+lint tool has emerged for PHP the way Biome/ruff have elsewhere. |
| Test + coverage | **Pest** (new projects, esp. Laravel-ecosystem); PHPUnit if already the convention | Detect from existing test files rather than defaulting blindly on an existing repo. |
| Mutation testing | **Infection** | The standard, mature option — MSI target of 85–90% scoped to business logic, not the whole codebase; `--git-diff-filter=A` for diff-mode on PRs. |
| Dependency audit | **`composer audit`** (built-in since Composer 2.4+) | No extra tool needed; require Composer ≥2.10 for its native malware-detection metadata (Packagist now surfaces Aikido-powered scan results directly). |
| Hook manager | **CaptainHook** (PHP-native config) or Lefthook (polyglot) | |
| Install | `composer require --dev captainhook/captainhook && vendor/bin/captainhook install` | |
| Dry-run / verify | `vendor/bin/captainhook validate` (or `lefthook run pre-commit --all-files` if using Lefthook) | |

## When a stack isn't listed here

Web-search for the ecosystem's current idiomatic linter, formatter, type
checker (if applicable), test runner, mutation-testing tool (if one
exists and is CI-mature), and dependency-audit command. Cross-check that
what you find is still maintained and not superseded — a two-year-old blog
post recommending a now-abandoned tool is worse than admitting uncertainty
and asking the user what they already use.
