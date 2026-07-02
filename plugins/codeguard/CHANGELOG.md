# Changelog

## 0.8.0 — 2026-07-02

- New `status` skill (`/codeguard:status`): read-only health check of a
  repo's safeguards — wired, drifted, or missing.
- Renamed the `codeguard-setup` skill to `setup`: invoke as
  `/codeguard:setup` (was `/codeguard:codeguard-setup`).
- DoD Stop-hook script now ships as a template
  (`skills/setup/assets/dod-check.sh`); no hard `jq` dependency, and its
  `.claude/.dod-attempts` state file gets gitignored at setup time.
- README overhaul: what you get, safety model, requirements, update and
  uninstall/undo instructions.
- CI reference: example action pin is now a placeholder, not a stale SHA.

## 0.7.1

- Initial published version: `codeguard-setup` skill with stack
  detection, safeguards catalog, and git-hooks / CI / devcontainers /
  agent-guardrails references.
