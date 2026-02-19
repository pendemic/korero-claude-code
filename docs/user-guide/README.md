# Korero User Guide

This guide helps you get started with Korero and understand how to configure it effectively for your projects.

## Guides

### [Quick Start: Your First Korero Project](01-quick-start.md)
A hands-on tutorial that walks you through enabling Korero on an existing project and running your first autonomous development loop. You'll build a simple CLI todo app from scratch.

### [Understanding Korero Files](02-understanding-korero-files.md)
Learn which files Korero creates, which ones you should customize, and how they work together. Includes a complete reference table and explanations of file relationships.

### [Writing Effective Requirements](03-writing-requirements.md)
Best practices for writing PROMPT.md, when to use specs/, and how fix_plan.md evolves during development. Includes good and bad examples.

## Example Projects

Check out the [examples/](../../examples/) directory for complete, realistic project configurations:

- **[simple-cli-tool](../../examples/simple-cli-tool/)** - Minimal example showing core Korero files
- **[rest-api](../../examples/rest-api/)** - Medium complexity with specs/ directory usage

## Quick Reference

| I want to... | Do this |
|-------------|---------|
| Enable Korero on an existing project | `korero-enable` |
| Import a PRD/requirements doc | `korero-import requirements.md project-name` |
| Create a new project from scratch | `korero-setup my-project` |
| Start Korero with monitoring | `korero --monitor` |
| Check what Korero is doing | `korero --status` |

## Need Help?

- **[Main README](../../README.md)** - Full documentation and configuration options
- **[CONTRIBUTING.md](../../CONTRIBUTING.md)** - How to contribute to Korero
- **[GitHub Issues](https://github.com/frankbria/korero-claude-code/issues)** - Report bugs or request features
