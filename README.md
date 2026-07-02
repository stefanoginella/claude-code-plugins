# Claude Code Plugins

Personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin
marketplace by [Stefano Ginella](https://www.stefanoginella.com).

## Add the marketplace

```
/plugin marketplace add stefanoginella/claude-code-plugins
```

Then install any plugin below with `/plugin install <name>`.

## Plugins

| Plugin | Description |
|---|---|
| [`codeguard`](plugins/codeguard) | Detects a repo's tech stack and sets up tailored quality & security safeguards — git hooks, CI, secret/SAST/dependency scanning, and coding standards baked into agent instructions — to prevent AI-generated slop and enforce best practices. |
| `aicontainer-setup` | Sourced from [stefanoginella/aicontainer](https://github.com/stefanoginella/aicontainer) — sets up the [aicontainer](https://github.com/stefanoginella/aicontainer) devcontainer for a project. |

Each plugin's own README has install/usage details.

## License

MIT — see [LICENSE](LICENSE).
