# AGENT.md

This file provides guidance to AI agents when working with code in this repository.

## Purpose

This repository stores AI agent configuration files for the **fdc-ota** and **remote-ota** projects (Foxtron EV firmware OTA systems). It is not the project source code — it holds the docs and agent guidance that get symlinked into project worktrees.

## Repository Structure

### global

- `global/codex/AGENTS.md` — Global Codex agent rules shared across environments.
- `setup-global-agent-env.sh` — Script that symlinks `~/.codex/AGENTS.md` to `global/codex/AGENTS.md`.

### fdc-ota

- `fdc-ota/AGENTS.md` — Authoritative AI agent entry point for the fdc-ota project. This is the primary file agents read when working in a fdc-ota worktree.
- `fdc-ota/docs/` — Architecture, protocol, vehicle model, development, and pitfalls documentation for fdc-ota.
- `fdc-ota/.claude/settings.local.json` — Claude Code permissions scoped to fdc-ota worktrees.
- `setup-worktree-env.sh` — Script that symlinks `AGENTS.md`, `CLAUDE.md`, and `docs/` from this repo into a new fdc-ota git worktree, and configures git to ignore those symlinks.

### remote-ota

- `remote-ota/AGENTS.md` — Authoritative AI agent entry point for the remote-ota project.
- `remote-ota/docs/` — Architecture, protocol, and development documentation for remote-ota.
- `setup-worktree-env-remote-ota.sh` — Script that symlinks `AGENTS.md`, `CLAUDE.md`, and `docs/` from this repo into a new remote-ota git worktree, and configures git to ignore those symlinks.

## Workflow: Setting Up a New Worktree

### global Codex config

When setting up Codex on a machine, run:

```bash
bash ~/Agent-config/setup-global-agent-env.sh
```

### fdc-ota worktree

When a new fdc-ota worktree is created, run from inside that worktree directory:

```bash
bash ~/Agent-config/setup-worktree-env.sh
```

### remote-ota worktree

When a new remote-ota worktree is created, run from inside that worktree directory:

```bash
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
```

Both scripts create symlinks so the worktree always reads the latest agent config from this repo, and add the symlinked names to both `~/.gitignore_global` and the worktree-local `.git/info/exclude`.

## Issue Tracking

When you encounter a potential problem (bug, risk, or code smell), append it to `ISSUES.md` in the working directory:

```
- [ ] [problem description] (location: filename:line_number)
```

Do not create `ISSUES.md` proactively — only write to it when an actual issue is found.

## Plans

Store implementation plans under `fdc-ota/docs/plan/`. One file per plan, e.g. `fdc-ota/docs/plan/feature-name.md`.

## Maintenance

- When fdc-ota agent configs need updating, edit files under `fdc-ota/` here and commit. All worktrees pick up the changes immediately via symlinks.
- When an agent makes a mistake on the fdc-ota project, add an entry to `fdc-ota/docs/pitfalls.md` and commit with: `docs: agent pitfall — <short description>`.
- Note: `setup-worktree-env.sh` references `fdc-ota/CLAUDE.md` which no longer exists (it was merged into `AGENTS.md`). Either remove that symlink from the script or recreate the file if Claude-specific guidance diverges from the shared AGENTS.md.
