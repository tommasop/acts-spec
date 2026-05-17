# Migration Guide

## Upgrading from v0.6.x to v1.x

ACTS v1.0.0 replaced the JSON-based state backend with a SQLite database and consolidated all tooling into a single Zig binary. This guide covers the one-time migration steps.

### What Changed

| Legacy (v0.6.x) | New (v1.x) |
|-----------------|------------|
| `.story/state.json` | `.acts/acts.db` (SQLite) |
| `.acts/lib/*.py` | `acts` binary |
| `.acts/mcp-server/` | Removed (use binary directly) |
| Python/TypeScript scripts | Single Zig executable |
| Manual JSON edits | `acts state write` command |

### Migration Steps

#### 1. Backup

```bash
cp -r .acts/ .acts.backup/
cp -r .story/ .story.backup/
```

#### 2. Install the v1.x Binary

```bash
# Linux
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.1.3/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts /usr/local/bin/

# macOS (aarch64)
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.1.3/acts-macos-aarch64.tar.gz | tar xz
sudo mv acts /usr/local/bin/
```

Or build from source:

```bash
cd acts-core
zig build -Doptimize=ReleaseSafe -Dversion=1.1.3
sudo cp zig-out/bin/acts /usr/local/bin/
```

#### 3. Migrate State from state.json to SQLite

If you have a `.story/state.json` file, import it into the database:

```bash
# Initialize ACTS first (creates the SQLite database)
acts init <story-id> --title "Your Story Title"

# Import old state
cat .story/state.json | acts state write --story <story-id>
```

Verify the migration worked:

```bash
acts state read
```

#### 4. Remove Legacy Files

After confirming the migration succeeded:

```bash
# Remove old state file (now in SQLite)
rm .story/state.json

# Remove legacy Python library
rm -rf .acts/lib/

# Remove legacy MCP server
rm -rf .acts/mcp-server/
```

#### 5. Update .acts/acts.json Manifest

Update the `manifest_version` to reflect the current version:

```json
{
  "manifest_version": "1.1.3",
  ...
}
```

#### 6. Validate

```bash
acts validate
```

Expected output:
```
Schema version: 6
Found: .story/plan.md
Found: .story/spec.md
Found: .story/sessions/

Validation PASSED
```

### What Stays the Same

| File | Status |
|------|--------|
| `.story/plan.md` | Unchanged |
| `.story/spec.md` | Unchanged |
| `.story/sessions/*.md` | Unchanged |
| `.story/tasks/<id>/notes.md` | Unchanged |
| `.acts/acts.json` | Unchanged (config manifest) |

### Troubleshooting

#### "state.json not found"

You may have scripts or docs referencing `.story/state.json`. Update them to use:

```bash
acts state read              # Human-readable
acts state read --format json  # Machine-readable (for agents)
```

#### Schema migration failed

Force a schema migration:

```bash
acts migrate
```

#### Restore from backup

If something goes wrong:

```bash
rm -rf .acts/ .story/
cp -r .acts.backup/ .acts/
cp -r .story.backup/ .story/
```

---

## Upgrading Between v1.x Versions

Minor version upgrades within v1.x only require replacing the binary. The SQLite schema auto-migrates on first run:

```bash
# Replace binary
acts migrate  # optional, happens automatically on next command

acts validate  # verify
```

Check schema version:

```bash
acts validate | head -1
# Schema version: 6
```
