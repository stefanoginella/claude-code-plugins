# Contributing

This repository is a Claude Code plugin marketplace — a catalog that points to individual plugin repositories.

## Marketplace Contributions

For marketplace-level changes (adding/removing plugins, updating metadata):

1. Fork this repository
2. Make your changes to `.claude-plugin/marketplace.json`
3. Submit a pull request

## Plugin Contributions

For changes to individual plugins, please contribute directly to the plugin's repository:

- **auto-bmad**: [github.com/stefanoginella/auto-bmad](https://github.com/stefanoginella/auto-bmad)
- **code-guardian**: [github.com/stefanoginella/code-guardian](https://github.com/stefanoginella/code-guardian)

Each plugin repo has its own CONTRIBUTING.md with setup instructions, design patterns, and guidelines.

## Local Development

For local development, clone the plugin repos into `plugins/` (gitignored by the marketplace):

```bash
mkdir -p plugins
git clone git@github.com:stefanoginella/auto-bmad.git plugins/auto-bmad
git clone git@github.com:stefanoginella/code-guardian.git plugins/code-guardian
```

Test a plugin locally:

```bash
claude --plugin-dir plugins/auto-bmad
claude --plugin-dir plugins/code-guardian
```

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE.md).
