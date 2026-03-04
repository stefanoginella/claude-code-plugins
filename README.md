# Claude Code Plugins

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE) [![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin_Marketplace-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

My collection of opinionated Claude Code plugins — built by a solo dev for solo devs.

I'm a freelance developer exploring what AI-assisted development can actually look like when you give it real structure. These plugins are my experiments in that space, and I hope they can be useful to other developers too.

## Available Plugins

> This repository serves as a marketplace for multiple plugins. Each plugin is developed and maintained in its own repository, but they are all listed here for easy discovery and installation.

| Plugin | Description | Repo |
|--------|-------------|------|
| auto-bmad | Automated and opinionated BMAD pipeline orchestration | [stefanoginella/auto-bmad](https://github.com/stefanoginella/auto-bmad) |
| code-guardian | EXPERIMENTAL: Deterministic + AI security scanning layer | [stefanoginella/code-guardian](https://github.com/stefanoginella/code-guardian) |

## Installation

Add the marketplace from the **Marketplace** tab of `/plugin` or directly:

```
/plugin marketplace add stefanoginella/claude-code-plugins
```

Then install a plugin:

```
/plugin install auto-bmad@stefanoginella-plugins
/plugin install code-guardian@stefanoginella-plugins
```

Or one-command install via npx:

```bash
npx @stefanoginella/auto-bmad
npx @stefanoginella/code-guardian
```

See each plugin's README for full documentation and prerequisites.

## Contributing

For issues or contributions to a specific plugin, please open them in the plugin's own repository:

- [auto-bmad issues](https://github.com/stefanoginella/auto-bmad/issues)
- [code-guardian issues](https://github.com/stefanoginella/code-guardian/issues)

For marketplace-level issues (adding/removing plugins, marketplace metadata), open an issue in this repository. See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for community guidelines.

## Disclaimer

- **Experimental software.** These plugins are provided as-is, with no guarantees of stability, correctness, or fitness for production use. Use at your own risk.
- **Token usage.** Plugin operations can consume significant API tokens and credits. Pipelines involving multiple agents or long-running tasks may be especially costly. Monitor your usage.
- **AI-generated output.** All content produced by these plugins is AI-generated. Always review outputs before acting on them or committing them to your project.

## License

[MIT License](./LICENSE)
