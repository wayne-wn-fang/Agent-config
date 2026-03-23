# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository stores AI agent configuration files for the **fdc-ota** project (Foxtron EV firmware OTA update system). It is not the fdc-ota source code — it holds the docs and agent guidance that get symlinked into fdc-ota worktrees.

## Repository Structure

- `fdc-ota/AGENTS.md` — Authoritative AI agent entry point for the fdc-ota project. This is the primary file agents read when working in a fdc-ota worktree.
- `fdc-ota/docs/` — Architecture, protocol, vehicle model, development, and pitfalls documentation for fdc-ota.
- `fdc-ota/.claude/settings.local.json` — Claude Code permissions scoped to fdc-ota worktrees.
- `setup-worktree-env.sh` — Script that symlinks `AGENTS.md`, `CLAUDE.md`, and `docs/` from this repo into a new fdc-ota git worktree, and configures git to ignore those symlinks.

## Workflow: Setting Up a New Worktree

When a new fdc-ota worktree is created, run from inside that worktree directory:

```bash
bash ~/Agent-config/setup-worktree-env.sh
```

This creates symlinks so the worktree always reads the latest agent config from this repo, and adds the symlinked names to both `~/.gitignore_global` and the worktree-local `.git/info/exclude`.

## Maintenance

- When fdc-ota agent configs need updating, edit files under `fdc-ota/` here and commit. All worktrees pick up the changes immediately via symlinks.
- When an agent makes a mistake on the fdc-ota project, add an entry to `fdc-ota/docs/pitfalls.md` and commit with: `docs: agent pitfall — <short description>`.
- Note: `setup-worktree-env.sh` references `fdc-ota/CLAUDE.md` which no longer exists (it was merged into `AGENTS.md`). Either remove that symlink from the script or recreate the file if Claude-specific guidance diverges from the shared AGENTS.md.
