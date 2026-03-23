# Agent-config

AI agent configuration and documentation for the **fdc-ota** project (Foxtron EV firmware OTA update system).

## What's Here

| Path | Purpose |
|---|---|
| `fdc-ota/AGENTS.md` | Authoritative AI agent entry point for fdc-ota — build commands, workspace layout, feature flags, coding conventions, pitfalls |
| `fdc-ota/docs/` | Architecture, protocols, vehicle models, development environment, and agent pitfall log |
| `fdc-ota/.claude/settings.local.json` | Claude Code permissions for fdc-ota worktrees |
| `setup-worktree-env.sh` | Sets up a new fdc-ota git worktree with symlinks to this config |

## Setting Up a New Worktree

After creating a new fdc-ota worktree, run from inside it:

```bash
bash ~/Agent-config/setup-worktree-env.sh
```

This symlinks `AGENTS.md`, `CLAUDE.md`, and `docs/` into the worktree and configures git to ignore them.

## Maintenance

Edit files under `fdc-ota/` and commit here. All worktrees pick up changes immediately via symlinks.

When an agent makes a mistake on the fdc-ota project, add an entry to `fdc-ota/docs/pitfalls.md`:

```bash
git commit -m "docs: agent pitfall — <short description>"
```
