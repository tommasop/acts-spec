# Updating ACTS

The ACTS framework lives in `.acts/` and can be updated independently of your project code.

## First-Time Setup (Existing Project)

If you have an existing ACTS project and want to add the update tool:

```bash
# One-liner migration to v0.6.0 (adds update tool, bin tools, updated operations/schemas)
curl -sL https://raw.githubusercontent.com/tommasop/acts-spec/main/scripts/migrate-to-v0.6.0.sh | bash

# Or if you have the acts-spec repo locally:
/path/to/acts-spec/scripts/migrate-to-v0.6.0.sh

# Dry run (show what would change):
curl -sL ... | bash -s -- --dry-run
```

**What the migration does:**

1. Detects your current ACTS version
2. Creates backup in `.acts/backup/vX.Y.Z/`
3. Updates framework files (operations, schemas, report-protocol)
4. Merges `.acts/acts.json` (preserves your config, adds new fields)
5. Installs `.acts/bin/acts-update` and `.acts/bin/acts-validate`
6. Validates the result
7. Commits changes

**What's preserved:**

- `.acts/acts.json` — your project config (review provider, integrations, etc.)
- `.acts/review-providers/` — your provider configs
- `.story/` — all story data (state, sessions, reviews)
- `AGENTS.md` — your project constitution

**After migration, you'll have:**

- `.acts/bin/acts-update` — update tool
- `.acts/bin/acts-validate` — validation tool
- All v0.6.0 operations (15 files)
- Updated schemas
- Backup of your previous installation

## Ongoing Updates

Once you have the update tool, use it for future updates:

```bash
# Check if updates are available
.acts/bin/acts-update --check

# Preview what would change
.acts/bin/acts-update --dry-run

# Apply update (creates backup first)
.acts/bin/acts-update

# Force re-apply framework files (even if version matches)
.acts/bin/acts-update --force

# Restore from backup
.acts/bin/acts-update --restore v0.6.0

# Skip confirmation (CI/scripts)
ACTS_UPDATE_YES=true .acts/bin/acts-update
```

## What Gets Updated

| File | Updated? | Notes |
|------|----------|-------|
| `.acts/operations/*.md` | ✅ | Operation definitions |
| `.acts/schemas/*.json` | ✅ | JSON schemas |
| `.acts/report-protocol.md` | ✅ | Report formats |
| `.acts/code-review-interface.json` | ✅ | Interface spec |
| `.acts/acts.json` | 🔀 Merged | Project config preserved, new fields added |
| `.acts/review-providers/` | ❌ | Preserved as-is |
| `.acts/adapters/` | ❌ | Preserved as-is |
| `.story/` | ❌ | Story data untouched |
| `AGENTS.md` | ❌ | Constitution untouched |

## Config Merge

When updating, `acts.json` is merged:

```json
{
  "manifest_version": "0.6.0",     ← Updated to latest
  "review_provider": "githuman",    ← Preserved (your choice)
  "agent_framework": {...},         ← Preserved (your config)
  "gh_stack": {...},                ← Preserved (your config)
  "new_field": "default"            ← Added (new in this version)
}
```

Your project-specific fields are never overwritten.

## Force Mode

Use `--force` when:

- You manually edited framework files and want to restore clean versions
- A framework file was corrupted and needs re-applying
- You want to ensure framework files match the expected state

Force does NOT touch project config — only framework files.

## Backup Structure

```
.acts/backup/
└── v0.5.0/
    ├── manifest.json          ← Backup metadata
    ├── acts.json              ← Full config backup
    ├── operations/            ← All operation files
    └── schemas/               ← All schema files
```

Each backup is self-contained and can restore the exact state.

## Troubleshooting

**"Could not determine latest version"**
- The tool looks for `acts-v*.md` in the project root
- Ensure you have at least one `acts-vX.Y.Z.md` file

**"No changes to commit"**
- Framework files already match the target version
- Use `--force` to re-apply even if no version change

**Validation fails after update**
- Review `.acts/acts.json` for merge issues
- Run `--restore` to rollback
- Check `python3 -m json.tool .acts/acts.json` for JSON errors

**Restore not found**
- Backup directories are in `.acts/backup/`
- List available backups: `ls .acts/backup/`
