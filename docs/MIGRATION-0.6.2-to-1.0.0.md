# Migrating from ACTS 0.6.2 to 1.0.0

This guide walks through migrating an existing ACTS 0.6.2 project to the new SQLite-backed v1.0.0 binary.

---

## What's Changed

| 0.6.2 | 1.0.0 | Action Required |
|-------|-------|-----------------|
| `.story/state.json` | `.acts/acts.db` (SQLite) | **Migrate data** |
| Python scripts (`.acts/lib/`) | Zig binary (`acts`) | **Install binary** |
| TypeScript MCP server (`.acts/mcp-server/`) | Removed | **Delete** |
| Bash scripts (`.acts/bin/acts-update`, `acts-validate`) | `acts` CLI | **Delete old, use new** |
| Operation definitions (`.acts/operations/*.md`) | Removed | **Delete** |
| JSON schemas (`.acts/schemas/*.json`) | Embedded in binary | **Delete** |
| `acts-update` for updates | `acts migrate` | **Use new command** |
| `acts-validate` bash script | `acts validate` | **Use new command** |

---

## Before You Start

**1. Backup your project**

```bash
git add -A
git commit -m "backup: pre-migration to ACTS 1.0.0"
```

**2. Ensure your `.story/state.json` is valid**

```bash
# Check it's valid JSON
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
# Requires Zig 0.13.0
git clone https://github.com/tommasop/acts-spec.git
cd acts-spec/acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/
```

Verify:
```bash
acts help
# Should show: ACTS Core v1.0.0
```

---

## Step 2: Migrate State to SQLite

**Create the SQLite database from your existing state.json:**

```bash
# Initialize the new database structure
acts init $(jq -r '.story_id' .story/state.json) --title "$(jq -r '.title' .story/state.json)"

# Migrate story fields
jq -n \
  --arg title "$(jq -r '.title' .story/state.json)" \
  --arg status "$(jq -r '.status' .story/state.json)" \
  --argjson spec_approved "$(jq '.spec_approved' .story/state.json)" \
  --argjson context_budget "$(jq '.context_budget' .story/state.json)" \
  --argjson strict_mode "$(jq '.strict_mode // false' .story/state.json)" \
  '{title: $title, status: $status, spec_approved: $spec_approved, context_budget: $context_budget, strict_mode: $strict_mode}' \
  | acts state write --story "$(jq -r '.story_id' .story/state.json)"

# Migrate tasks
jq -c '.tasks[]' .story/state.json | while read -r task; do
  story_id=$(jq -r '.story_id' .story/state.json)
  echo "[$story_id]" | jq --argjson task "$task" '{tasks: [$task]}' | acts state write --story "$story_id"
done
```

**Alternative: Python migration script**

If you have Python available, create `migrate.py`:

```python
#!/usr/bin/env python3
import json
import subprocess
import sys

def migrate_state(json_path):
    with open(json_path) as f:
        state = json.load(f)
    
    story_id = state['story_id']
    
    # Initialize
    subprocess.run(['acts', 'init', story_id, '--title', state['title']], check=True)
    
    # Write story fields
    story_update = {
        'title': state['title'],
        'status': state['status'],
        'spec_approved': state.get('spec_approved', False),
        'context_budget': state.get('context_budget', 50000),
        'strict_mode': state.get('strict_mode', False),
    }
    proc = subprocess.Popen(
        ['acts', 'state', 'write', '--story', story_id],
        stdin=subprocess.PIPE,
        text=True
    )
    proc.communicate(json.dumps(story_update))
    proc.wait()
    
    # Write tasks
    for task in state.get('tasks', []):
        task_data = {
            'tasks': [task]
        }
        proc = subprocess.Popen(
            ['acts', 'state', 'write', '--story', story_id],
            stdin=subprocess.PIPE,
            text=True
        )
        proc.communicate(json.dumps(task_data))
        proc.wait()
    
    print(f"Migrated story {story_id} with {len(state.get('tasks', []))} tasks")

if __name__ == '__main__':
    migrate_state('.story/state.json')
```

Run:
```bash
python3 migrate.py
```

---

## Step 3: Verify Migration

```bash
# Check state in SQLite
acts state read

# Should show your story with all tasks
# Compare with old state:
# cat .story/state.json
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

# Test gate enforcement (create a test task first)
# This should FAIL without preflight gate:
acts task update T1 --status IN_PROGRESS
# → "Cannot start task: preflight gate not approved"

# Add gate and retry:
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS
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
- name: Setup Zig
  uses: mlugg/setup-zig@v1
  with:
    version: 0.13.0

- name: Build ACTS
  working-directory: ./acts-core
  run: zig build release

- name: Validate ACTS
  run: ./acts-core/zig-out/bin/acts validate
```

Or download pre-built binary:
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

Check the migration script output. If tasks weren't migrated:
```bash
# Manual insert
sqlite3 .acts/acts.db "INSERT INTO tasks (id, story_id, title, description, status) VALUES ('T1', 'PROJ-42', 'Title', 'Desc', 'TODO');"
```

### Binary not in PATH

If `acts` command not found:
```bash
# Use absolute path or add to PATH
export PATH="$PATH:/path/to/acts"
```

---

## Rollback

If something goes wrong:

```bash
# Restore old state.json from git
git checkout HEAD -- .story/state.json

# Restore old scripts
git checkout HEAD -- .acts/lib .acts/mcp-server .acts/operations .acts/schemas

# Remove SQLite database
rm .acts/acts.db
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
