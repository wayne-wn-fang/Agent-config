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

The `~/remote-ota/docs/` directory will be removed from the remote-ota repo and replaced with a symlink pointing to `Agent-config/remote-ota/docs/`.

---

## 3. Setup Script (`setup-worktree-env-remote-ota.sh`)

Structurally identical to `setup-worktree-env.sh`, with `CONFIG_BASE` pointing to the remote-ota config:

```bash
CONFIG_BASE="$HOME/Agent-config/remote-ota"
```

**Steps performed by the script:**

1. Create symlinks in the worktree (using `ln -sf` / `ln -sfn` to overwrite any pre-existing symlink):
   - `AGENTS.md` → `$HOME/Agent-config/remote-ota/AGENTS.md`
   - `CLAUDE.md` → `$HOME/Agent-config/remote-ota/AGENTS.md` (both point to remote-ota's AGENTS.md)
   - `docs/` → `$HOME/Agent-config/remote-ota/docs/`
2. Add `AGENTS.md`, `CLAUDE.md`, `docs`, `docs/` to `~/.gitignore_global` (idempotent — skip if already present)
3. Add the same entries to the worktree-local `.git/info/exclude`
4. Symlink `~/.claude/settings.json` → `~/Agent-config/claude/settings.json`
5. Symlink `~/.claude/hooks/validate-commit.sh` → `~/Agent-config/claude/validate-commit.sh`
6. Symlink `~/.claude/commands/pr-review.md` → `~/Agent-config/claude/pr-review.md`

**Edge case — pre-existing directory:** If `./docs` already exists as a real directory (not a symlink) in the worktree, the script must remove it first before creating the symlink. The script should check with `[ -d ./docs ] && [ ! -L ./docs ]` and abort with an error message asking the developer to manually resolve the conflict.

**Edge case — tracked files:** The script does not need to check whether AGENTS.md/docs are tracked by git in the worktree; `ln -sf` and `ln -sfn` will overwrite safely, and the gitignore entries will prevent them from being staged.

**Usage:**
```bash
# From inside a new remote-ota worktree
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
```

---

## 4. `remote-ota/AGENTS.md` Content Outline

The file follows the same structure as `fdc-ota/AGENTS.md`. Sections and content:

### 4.1 Purpose
Two sentences: what `remote-ota` does (single-shot OTA trigger/monitor tool in Rust, for FDC vehicle devices over AWS IoT Core MQTT) and the role of this Agent-config directory (authoritative source for agent guidance and docs, symlinked into worktrees).

### 4.2 Repository Structure
Table of the source modules and their single responsibility each (based on current main branch — `session.rs` exists only in a worktree branch and should be documented once merged):

| File | Responsibility |
|------|---------------|
| `src/main.rs` | CLI parsing, MQTT setup, single-shot orchestration, exit-code mapping |
| `src/messages.rs` | Protocol payload building and JSON parsing helpers |
| `src/topics.rs` | MQTT topic construction helpers |

### 4.3 Verification Commands
```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```
All three must pass before committing.

### 4.4 Issue Tracking
When an issue is found, append to `ISSUES.md`:
```
- [ ] [problem description] (location: filename:line_number)
```
Do not create `ISSUES.md` proactively.

### 4.5 Plans
Store implementation plans under `docs/superpowers/plans/`. One file per plan, e.g. `docs/superpowers/plans/feature-name.md`.

### 4.6 Key Invariants (Agents Must Not Violate)
- **Single-shot:** One invocation performs exactly one OTA attempt and then exits. Do not add retry loops.
- **VIN safety:** A VIN mismatch must always exit with code `2`. Never relax or bypass this check.
- **AttemptId correlation:** Correlation is strict string equality on the top-level `attemptId` field. Never accept a message with a missing or non-matching `attemptId`.
- **Dual-topic publishing:** Probe and launch commands must always be published to both the legacy and IOV run-cmd topics. Never publish to only one.
- **Exit codes:** Exit `0` = success, `1` = general failure, `2` = VIN mismatch. Do not change this mapping.

---

## 5. Migration Steps (remote-ota repo)

Perform in this exact order to avoid losing content:

1. **Copy first:** Copy `~/remote-ota/docs/` to `~/Agent-config/remote-ota/docs/` before touching git.
   ```bash
   cp -r ~/remote-ota/docs/ ~/Agent-config/remote-ota/docs/
   ```

2. **Remove from remote-ota git:** In `~/remote-ota`:
   ```bash
   git rm -r docs/
   git commit -m "chore: remove docs (moved to Agent-config)"
   ```

3. **Create symlink in main remote-ota working directory:**
   ```bash
   ln -sfn ~/Agent-config/remote-ota/docs ~/remote-ota/docs
   ```

4. **Exclude symlink from git tracking** (main repo's local exclude, not per-worktree):
   ```bash
   echo "docs" >> ~/remote-ota/.git/info/exclude
   echo "docs/" >> ~/remote-ota/.git/info/exclude
   ```

5. **Verification:** Run the following to confirm the symlink works:
   ```bash
   cat ~/remote-ota/docs/remote-ota.md | head -5
   # Should print the remote-ota.md header from Agent-config
   ```

6. **Create a test worktree** to validate end-to-end setup:
   ```bash
   git -C ~/remote-ota worktree add /tmp/test-remote-ota-wt
   cd /tmp/test-remote-ota-wt
   bash ~/Agent-config/setup-worktree-env-remote-ota.sh
   cat docs/remote-ota.md | head -5  # must show content from Agent-config
   git -C ~/remote-ota worktree remove /tmp/test-remote-ota-wt
   ```

---

## 6. CLAUDE.md Update

Add the following section to `Agent-config/CLAUDE.md`, immediately after the existing `fdc-ota` section:

```markdown
## remote-ota Project

- `remote-ota/AGENTS.md` — Authoritative AI agent entry point for the remote-ota project.
- `remote-ota/docs/` — Architecture, protocol, and development documentation for remote-ota.

### Workflow: Setting Up a New Worktree

When a new remote-ota worktree is created, run from inside that worktree directory:

    bash ~/Agent-config/setup-worktree-env-remote-ota.sh

This creates symlinks so the worktree always reads the latest agent config from this repo,
and adds the symlinked names to both `~/.gitignore_global` and the worktree-local `.git/info/exclude`.
```

---

## 7. Out of Scope

- Modifying the existing `setup-worktree-env.sh` (fdc-ota script unchanged)
- Merging both setup scripts into one (deferred)
- CI or build automation changes in remote-ota
