# Devcontainers & aicontainer

Detect this in the same pass as stack detection (SKILL.md step 1), not
after the plan is built — it constrains what can actually be installed
live versus what has to be routed to a Dockerfile and a rebuild, and that
needs to be visible in the proposal, not discovered partway through setup.

## Detecting which environment you're in

| Environment | Markers |
|---|---|
| **aicontainer** | `AIC_TOOLS` / `AIC_SHELL` env vars set, root-owned `/etc/aic/` present on the filesystem, optionally `AIC_FREEZE_TOOLS=1` |
| **Generic devcontainer** | `.devcontainer/devcontainer.json` present, but none of the aicontainer markers above |
| **Host machine** | Neither — no `.devcontainer/` directory, no aicontainer env vars |

## aicontainer

([stefanoginella/aicontainer](https://github.com/stefanoginella/aicontainer))

- **Runtime `apt`/system-package installs are blocked outright.** `sudo` is
  scoped to a small set of specific wrapper scripts, not general command
  execution — a bare `sudo apt install <package>` will fail. This is by
  design, not a bug to work around.
- **The fix**: add the package to `.devcontainer/Dockerfile.project` and
  rebuild the container. This is the only path to a persistent system
  package — there's no runtime escape hatch, and there shouldn't be one to
  find.
- **Hook/tool installation that must survive a rebuild** goes in
  `.devcontainer/post-create.project.sh` — it runs as the `vscode` user
  from `/workspace` on every container create, after aicontainer's own
  setup. It's read-only from inside the container (the agent session can't
  self-modify it), and its presence is opt-in — if the project doesn't
  have one yet, proposing to add one is itself part of the safeguard.
- **What belongs where**:
  - System packages (a linter's native binary dependency, a runtime the
    hook manager needs) → `Dockerfile.project`, requires rebuild.
  - Project-scoped tooling installable via the language's own package
    manager (npm devDependencies, a `uv` tool install, `cargo install`
    pinned in CI) and hook-manager activation (`lefthook install`) →
    `post-create.project.sh`, survives rebuild without needing a new image.
  - Anything installable purely within the sandbox for *this session* →
    fine to do live, but say plainly that it won't survive a rebuild
    unless it's also added to one of the two files above.
- **Host-side state**: `~/.gitconfig` is read-only mounted from the host,
  and an `aic-auth-global` volume holds credentials/tool metadata shared
  across projects. This is host-managed — codeguard has no reason to touch
  either.

When aicontainer is detected, the setup step (SKILL.md §5) should still do
everything the sandbox permits live, and step 6 should hand back the exact
snippet to add to `Dockerfile.project` and/or `post-create.project.sh`,
plus a plain "rebuild the container to finish this" instruction. Don't
leave the user to infer that a rebuild is needed — say it outright.

## Generic devcontainer (not aicontainer)

No aicontainer-style block on runtime installs, but the same durability
problem exists in a milder form: anything installed live during a session
disappears on the next rebuild unless it's also captured in the
`Dockerfile` or the devcontainer's `postCreateCommand`. Warn about this
explicitly and point to whichever of those two the project already uses.

## Host machine (no container)

No install restrictions, but a different failure mode: CI runs in a clean
environment every time, so anything installed "by hand" locally during
this session won't be there when CI runs unless it's pinned and declared
in a manifest, lockfile, or CI setup step. Nothing installed in this
session is durable by default — durability comes from what ends up
committed.
