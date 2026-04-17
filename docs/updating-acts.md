# Updating ACTS

The ACTS framework lives in `.acts/` and can be updated independently of your project code.

## Quick Commands

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
