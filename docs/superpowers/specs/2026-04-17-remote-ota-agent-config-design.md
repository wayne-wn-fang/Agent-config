# Design: remote-ota Agent Config Integration

**Date:** 2026-04-17  
**Status:** Approved  
**Scope:** Extend Agent-config to manage remote-ota agent guidance and docs, with per-worktree setup script

---

## 1. Goal

Mirror the fdc-ota pattern for the `remote-ota` project: centralize agent guidance (`AGENTS.md`) and documentation (`docs/`) in `Agent-config`, and provide a setup script that symlinks them into each new `remote-ota` git worktree.

---

## 2. Directory Structure

After implementation, `Agent-config` will have a parallel structure for both projects:

```
Agent-config/
├── fdc-ota/
│   ├── AGENTS.md
│   └── docs/
├── remote-ota/
│   ├── AGENTS.md          ← new: agent guidance for remote-ota
│   └── docs/              ← moved from ~/remote-ota/docs/
│       ├── remote-ota.md
│       ├── protocol-spec.md
│       └── superpowers/
│           ├── plans/
│           └── specs/
└── setup-worktree-env-remote-ota.sh   ← new: per-worktree setup script
```

The `~/remote-ota/docs/` directory will be removed from the remote-ota repo (via `git rm -r`) and replaced with a symlink pointing to `Agent-config/remote-ota/docs/`.

---

## 3. Setup Script (`setup-worktree-env-remote-ota.sh`)

Structurally identical to `setup-worktree-env.sh`, with one change:

```bash
CONFIG_BASE="$HOME/Agent-config/remote-ota"
```

**Steps performed by the script:**

1. Create symlinks in the worktree:
   - `AGENTS.md` → `$CONFIG_BASE/AGENTS.md`
   - `CLAUDE.md` → `$CONFIG_BASE/AGENTS.md`
   - `docs/` → `$CONFIG_BASE/docs/`
2. Add `AGENTS.md`, `CLAUDE.md`, `docs`, `docs/` to `~/.gitignore_global`
3. Add the same entries to the worktree-local `.git/info/exclude`
4. Symlink `~/.claude/settings.json` → `Agent-config/claude/settings.json`
5. Symlink `~/.claude/hooks/validate-commit.sh` → `Agent-config/claude/validate-commit.sh`
6. Symlink `~/.claude/commands/pr-review.md` → `Agent-config/claude/pr-review.md`

**Usage:**
```bash
# From inside a new remote-ota worktree
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
```

---

## 4. `remote-ota/AGENTS.md` Content

The AGENTS.md will include:

- **Purpose** — single-shot OTA trigger tool (Rust), and role of this Agent-config directory
- **Repository Structure** — responsibilities of `src/main.rs`, `src/session.rs`, `src/messages.rs`, `src/topics.rs`
- **Verification Commands** — `cargo fmt --all -- --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test`
- **Issue Tracking** — append issues to `ISSUES.md` as `- [ ] [description] (location: file:line)`
- **Plans** — store under `docs/superpowers/plans/`
- **Key Invariants** — behavioral rules agents must not violate:
  - One invocation = one OTA attempt, then exit
  - VIN mismatch must always exit with code `2`
  - `attemptId` correlation is strict string equality; never relax this check
  - Both legacy and IOV run-cmd topics must always be published together

---

## 5. Migration Steps (remote-ota repo)

1. In `~/remote-ota`: `git rm -r docs/` and commit with message `chore: remove docs (moved to Agent-config)`
2. Copy `docs/` content into `Agent-config/remote-ota/docs/`
3. From `~/remote-ota` working directory: `ln -sfn ~/Agent-config/remote-ota/docs ./docs`
4. Add `docs` and `docs/` to `~/remote-ota/.git/info/exclude`

After this, all worktrees created from `remote-ota` that run the setup script will share the same docs via Agent-config.

---

## 6. CLAUDE.md Update

Add a section to `Agent-config/CLAUDE.md` documenting the `remote-ota` structure and the new setup script, parallel to the existing fdc-ota section.

---

## 7. Out of Scope

- Modifying the existing `setup-worktree-env.sh` (fdc-ota script unchanged)
- Merging both setup scripts into one (deferred, not needed now)
- CI or build automation changes in remote-ota
