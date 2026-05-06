# Migrating from ACTS 0.6.2 to 1.0.0

This guide walks through migrating an existing ACTS 0.6.2 project to the new SQLite-backed v1.0.0 binary.

The 0.6.2 `state.json` format has this structure:
```json
{
  "story": { "key": "...", "title": "...", "status": "...", ... },
  "acts": { "manifest_version": "0.6.2", "conformance_level": "...", ... },
  "tasks": [ { "id": "T1", "files_affected": [...], "dependencies": [...], ... } ],
  "sessions": [ { "id": "S1", "task_id": "T1", "summary": "...", ... } ],
  "rules": { ... }
}
```

This is migrated to SQLite `.acts/acts.db` and markdown files.

---

## What's Changed

| 0.6.2 | 1.0.0 | Action Required |
|-------|-------|-----------------|
| `.story/state.json` | `.acts/acts.db` (SQLite) | **Migrate data** |
| `story.key` | `stories.id` | **Mapped** |
| `story.status` (Jira) | `stories.status` (ACTS enum) | **Mapped** |
| `tasks[].files_affected` | `task_files` table | **Migrated** |
| `tasks[].dependencies` | `task_dependencies` table | **Migrated** |
| `tasks[].owner` | `tasks.assigned_to` | **Mapped** |
| `sessions[]` | `.story/sessions/*.md` | **Migrated** |
| `acts` config | `.acts/acts.json` (updated) | **Migrated** |
| Python scripts (`.acts/lib/`) | Zig binary (`acts`) | **Install binary** |
| TypeScript MCP server | Removed | **Delete** |
| Bash scripts (`acts-update`, `acts-validate`) | `acts` CLI | **Delete old** |
| Operation definitions | Removed | **Delete** |
| JSON schemas | Embedded in binary | **Delete** |

---

## Before You Start

**1. Backup your project**

```bash
git add -A
git commit -m "backup: pre-migration to ACTS 1.0.0"
```

**2. Ensure your `.story/state.json` is valid**

```bash
python3 -m json.tool .story/state.json > /dev/null && echo "Valid JSON"
```

---

## Step 1: Install the Binary

```bash
# Option A: Download pre-built binary
# Linux x86_64
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts-linux-x86_64 /usr/local/bin/acts

# macOS Apple Silicon
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-macos-aarch64.tar.gz | tar xz
sudo mv acts-macos-aarch64 /usr/local/bin/acts

# Option B: Build from source
cd acts-core && zig build release
sudo cp zig-out/bin/acts /usr/local/bin/
```

Verify:
```bash
acts help
# Should show: ACTS Core v1.0.0
```

---

## Step 2: Run the Migration Script

Download the migration script:

```bash
curl -L -o migrate-0.6.2-to-1.0.0.py \
  https://raw.githubusercontent.com/tommasop/acts-spec/main/migrate-0.6.2-to-1.0.0.py
```

Run it:

```bash
python3 migrate-0.6.2-to-1.0.0.py .story/state.json
```

The script will:
1. Initialize the database (`acts init <key> --title <title>`)
2. Migrate story fields (status, spec_approved, strict_mode)
3. Migrate all tasks with files_affected → task_files
4. Migrate all dependencies → task_dependencies
5. Create session markdown files from sessions[] array
6. Update `.acts/acts.json` with migrated config

Output:
```
Migrating story: WP-3630 — Coin Management Technical Specification
Tasks: 7
Sessions: 2

1. Initializing database...
2. Migrating story fields...
3. Migrating tasks...
   Task T1: Balance Core: Schema, Migration & Customer Read AP...
   Task T2: Transaction Ledger & Credit/Debit Operations...
   ...
4. Migrating sessions...
   Created: .story/sessions/20260429-120000-migrated.md
5. Updating .acts/acts.json...

✅ Migration complete!

Database: .acts/acts.db
Sessions: 2 files in .story/sessions/
Tasks: 7 migrated

6. Verification:
   Tasks in database: 7
   Files tracked: 25
   Dependencies: 8
```

---

## Step 3: Verify Migration

```bash
# Check state in SQLite
acts state read

# Should show your story with all tasks
# Compare with old state:
# cat .story/state.json | jq '.story, .tasks | length'
```

---

## Step 4: Remove Old Files

**Delete old Python/TypeScript code:**

```bash
rm -rf .acts/lib
rm -rf .acts/mcp-server
rm -rf .acts/operations
rm -rf .acts/schemas
rm -rf .acts/tests
rm -f .acts/bin/acts-update
rm -f .acts/bin/acts-validate
rm -f .acts/code-review-interface.json
rm -f .acts/report-protocol.md
rm -f .acts/update-manifest.json
```

**Remove old state.json (after confirming migration worked):**

```bash
# Only after verifying acts state read shows correct data
rm .story/state.json
```

**Clean up old backups:**

```bash
rm -rf .acts/backup
```

---

## Step 5: Update AGENTS.md

Replace the ACTS section in your `AGENTS.md`:

```markdown
## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0 for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion

### ACTS Commands
- `acts init <story-id>` — Initialize new ACTS story
- `acts state read` — Read current story state
- `acts state write --story <id>` — Update story state (JSON from stdin)
- `acts task get <task-id>` — Get task details
- `acts task update <id> --status <status>` — Update task status (enforces gates)
- `acts gate add --task <id> --type <type> --status <status>` — Add gate checkpoint
- `acts ownership map` — Show file ownership
- `acts scope check --task <id> --file <path>` — Check if file is safe to modify
- `acts validate` — Validate entire ACTS project
- `acts migrate` — Force schema migration

### Gate Protocol
1. Before starting task: `acts gate add --task <id> --type approve --status approved`
2. Before completing task: `acts gate add --task <id> --type task-review --status approved`

### Data Storage
- Structured state (stories, tasks, gates, decisions): SQLite at `.acts/acts.db`
- Narratives (plan, spec, sessions, notes): Markdown files in `.story/`
- `.story/state.json`: REMOVED (replaced by SQLite)

### OpenCode Plugin (optional)
If using OpenCode, add to `opencode.json`:
```json
{
  "plugin": ["./.opencode/plugins/acts.js"]
}
```
```

---

## Step 6: Test the New Setup

```bash
# Validate everything works
acts validate

# Test gate enforcement
cat .story/state.json  # Should NOT exist anymore

# Check ownership
acts ownership map

# This should FAIL without preflight gate:
acts task update T3 --status IN_PROGRESS
# → "Cannot start task: preflight gate not approved"

# Add gate and retry:
acts gate add --task T3 --type approve --status approved --by developer
acts task update T3 --status IN_PROGRESS
# → Success
```

---

## Step 7: Update CI/CD

If you had CI validating ACTS, update your workflow:

**Before (0.6.2):**
```yaml
- name: Validate ACTS
  run: .acts/bin/acts-validate --json
```

**After (1.0.0):**
```yaml
- name: Install ACTS
  run: |
    curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
    sudo mv acts-linux-x86_64 /usr/local/bin/acts

- name: Validate
  run: acts validate
```

---

## Troubleshooting

### "state.json not found" after migration

You may have scripts referencing `.story/state.json`. Update them to use:
```bash
acts state read
```

### Gate enforcement not working

Check triggers are installed:
```bash
sqlite3 .acts/acts.db ".schema trigger"
```

If empty, run:
```bash
acts migrate
```

### Tasks missing after migration

Check the migration script output. If tasks weren't migrated, the script will show errors. Common issues:
- `story.key` missing → script uses "UNKNOWN"
- `tasks[].id` missing → task is skipped
- Malformed JSON → script exits with error

### Sessions not migrated

Sessions are converted to markdown files in `.story/sessions/`. If missing:
- Check the script had write permissions
- Check `sessions` array existed in state.json
- Sessions with missing `task_id` are still created but may have "UNKNOWN" task reference

### Binary not in PATH

If `acts` command not found:
```bash
# Use absolute path or add to PATH
export PATH="$PATH:/path/to/acts/binary"
```

---

## Rollback

If something goes wrong:

```bash
# Restore old state.json from git
git checkout HEAD -- .story/state.json

# Restore old scripts (if you kept them in git)
git checkout HEAD -- .acts/lib .acts/mcp-server .acts/operations .acts/schemas

# Remove SQLite database
rm .acts/acts.db

# Remove migrated sessions
rm -rf .story/sessions/*-migrated.md
```

---

## Post-Migration Checklist

- [ ] `acts state read` shows correct story and tasks
- [ ] `.story/state.json` removed (or backed up)
- [ ] Old Python/TypeScript scripts removed
- [ ] `AGENTS.md` updated with new commands
- [ ] `acts validate` passes
- [ ] Gate enforcement works (test with a task)
- [ ] CI/CD updated for new binary
- [ ] Team notified of new workflow
