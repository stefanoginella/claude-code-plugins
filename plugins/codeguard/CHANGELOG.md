# Changelog

## 0.8.1 — 2026-07-02

- Setup re-runs now handle stack *removals* too: the inventory checks for
  stale safeguards aimed at stack components that no longer exist, and
  the proposal gains a "remove" group alongside add / change /
  leave-as-is. Marker-bearing files are proposed for removal; user-owned
  ones are flagged for the user to decide.
- Tier-5 governance now scales with contributor count, not just repo
  classification: a solo repo — even a commercial one — gets the
  solo-viable subset (required status checks, force-push protection,
  `SECURITY.md`), with `CODEOWNERS` and required reviews deferred until
  a second regular contributor arrives.
- Generated `SECURITY.md` defaults to a contact-free reporting channel
  with **no email**; an address is included only when the user
  explicitly chooses one.

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
