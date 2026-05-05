# ACTS Integration Guide

This guide covers integrating ACTS into different AI-assisted development workflows. Choose the approach that matches your editor/agent setup.

## Approaches Overview

| Approach | Best For | Setup Complexity | Agent Awareness |
|----------|----------|------------------|-----------------|
| **OpenCode Plugin** | OpenCode.ai users | Low (auto-injected) | Automatic |
| **Manual CLI** | Claude, Cursor, VS Code, other editors | Medium (AGENTS.md) | Manual commands |
| **MCP Server** | Future — any MCP-enabled client | TBD | Tool-based |

---

## OpenCode Plugin (Recommended)

The OpenCode plugin provides the most seamless integration. It injects ACTS context automatically and exposes a native `acts` tool.

### How It Works

```
User Message
    |
    v
[Plugin: experimental.chat.messages.transform]
    |
    +-- Injects ACTS bootstrap into first message
    |
    v
[Agent receives context + rules]
    |
    v
[Plugin: tools registration]
    |
    +-- Registers `acts` as native tool
    |
    v
[Agent calls acts tool]
    +-- Plugin executes binary
    +-- Returns JSON output
```

### Installation

**1. Install the binary:**

```bash
# Option A: Copy to project
cp acts-core/zig-out/bin/acts .acts/bin/acts

# Option B: Global install
sudo cp acts-core/zig-out/bin/acts /usr/local/bin/
```

**2. Configure OpenCode:**

Add to your project's `opencode.json` (or global `~/.config/opencode/opencode.json`):

```json
{
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git",
    "./.opencode/plugins/acts.js"
  ]
}
```

**3. Restart OpenCode.**

### What the Agent Sees

On the first message of every conversation, the agent receives:

```
<EXTREMELY_IMPORTANT>
This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0.

Rules:
- Read state before writing code: acts state read
- Do not modify files owned by DONE tasks: acts scope check --task <id> --file <path>
- Record session summary before ending: acts session validate <file.md>
- Stay within assigned task boundary
- Run code review before task completion: acts gate add --task <id> --type task-review --status approved
- Follow gate protocol: preflight gate required before starting task

ACTS commands:
- acts init <story-id>              Initialize new story
- acts state read                   Read current story state
- acts state write --story <id>     Update story state (JSON from stdin)
- acts task get <task-id>           Get task details
- acts task update <id> --status <s> Update task status (enforces gates)
- acts gate add --task <id> --type <t> --status <s>  Add gate checkpoint
- acts ownership map                Show file ownership
- acts scope check --task <id> --file <path> Check if file is safe to modify
- acts validate                     Validate entire ACTS project
- acts migrate                      Force schema migration

Gate Types:
- approve          Preflight approval (required before IN_PROGRESS)
- task-review      Code review approval (required before DONE)
- commit-review    Batch commit approval (strict mode)
- architecture-discuss Architecture decision approval (strict mode)

Status Values:
- TODO, IN_PROGRESS, BLOCKED, DONE (tasks)
- ANALYSIS, APPROVED, IN_PROGRESS, REVIEW, DONE (stories)
- pending, approved, changes_requested (gates)
</EXTREMELY_IMPORTANT>
```

### Native Tool Usage

The agent can call the `acts` tool directly:

```json
{
  "command": "acts state read"
}
```

Response:
```json
{
  "story_id": "PROJ-42",
  "status": "APPROVED",
  "tasks": [...]
}
```

### Workflow Example

```
User: "Implement the login endpoint for task T1"

Agent:
1. calls acts tool: "acts state read"
   → Receives current story state

2. calls acts tool: "acts scope check --task T1 --file src/routes/auth.ts"
   → Receives: { "action": "ok", "message": "Safe to modify" }

3. calls acts tool: "acts gate list --task T1"
   → Receives: [] (no gates yet)

4. calls acts tool: "acts gate add --task T1 --type approve --status approved --by developer"
   → Gate checkpoint added

5. calls acts tool: "acts task update T1 --status IN_PROGRESS"
   → Task status updated

6. [Implements code...]

7. calls acts tool: "acts gate add --task T1 --type task-review --status approved --by reviewer"
   → Review gate added

8. calls acts tool: "acts task update T1 --status DONE"
   → Task completed

9. Writes session summary to .story/sessions/

10. calls acts tool: "acts session validate .story/sessions/20260105-143022.md"
    → Validation passed
```

### Plugin File Structure

```
.opencode/
└── plugins/
    └── acts.js          # Plugin implementation
opencode.json            # Plugin registration
```

### Customization

Edit `.opencode/plugins/acts.js` to customize:
- Bootstrap content (rules, commands)
- Tool schema (additional parameters)
- Binary discovery logic

---

## Manual CLI (Claude, Cursor, VS Code, etc.)

For editors without plugin support, agents interact with ACTS through standard CLI commands.

### How It Works

```
User Message
    |
    v
[Agent reads AGENTS.md]
    |
    +-- Finds ACTS commands section
    |
    v
[Agent uses Bash tool to run commands]
    |
    +-- executes: acts state read
    +-- executes: acts task update T1 --status DONE
```

### Setup

**1. Install the binary:**

```bash
# Download pre-built binary
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts-linux-x86_64 /usr/local/bin/acts

# Or build from source
cd acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/
```

**2. Update AGENTS.md:**

Add ACTS context to your project's `AGENTS.md`:

```markdown
## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by DONE tasks: `acts scope check --task <id> --file <path>`
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
3. In strict mode: `acts gate add --task <id> --type commit-review --status approved`
```

**3. Initialize ACTS in your project:**

```bash
acts init PROJ-42 --title "Your Project"
```

### Workflow Example

```
User: "Implement the login endpoint for task T1"

Agent:
1. Bash: acts state read
   → Receives JSON state

2. Bash: acts scope check --task T1 --file src/routes/auth.ts
   → Receives: { "action": "ok" }

3. Bash: acts gate add --task T1 --type approve --status approved --by developer
   → Gate added

4. Bash: acts task update T1 --status IN_PROGRESS
   → Task started

5. [Implements code using Write/Edit tools...]

6. Bash: acts gate add --task T1 --type task-review --status approved --by reviewer
   → Review gate added

7. Bash: acts task update T1 --status DONE
   → Task completed

8. Write: .story/sessions/20260105-143022-alice.md
   → Session summary

9. Bash: acts session validate .story/sessions/20260105-143022-alice.md
   → Validation passed
```

### Platform-Specific Notes

**Claude Code:**
- AGENTS.md is automatically read at session start
- Use the Bash tool for all `acts` commands
- Consider adding `acts validate` to pre-commit checks

**Cursor:**
- Add ACTS rules to `.cursorrules` or project settings
- Use terminal for `acts` commands
- The agent should check `acts state read` before each coding session

**VS Code + Continue:**
- Add ACTS context to `.continue/config.json` system message
- Use terminal for binary execution

**Generic (Any Editor):**
- Ensure AGENTS.md is in project root
- Agent reads AGENTS.md via Read tool before coding
- All ACTS interactions via Bash tool

---

## Comparison: Plugin vs Manual

| Feature | OpenCode Plugin | Manual CLI |
|---------|----------------|------------|
| **Setup** | Add 2 lines to opencode.json | Update AGENTS.md, install binary |
| **Agent Awareness** | Automatic injection every session | Depends on agent reading AGENTS.md |
| **Command Interface** | Native tool (acts) | Bash tool executions |
| **Error Handling** | Plugin wraps errors in JSON | Raw stderr output |
| **Customizability** | Edit plugin JS | Edit AGENTS.md |
| **Cross-Platform** | Same (binary auto-discovered) | Same (binary must be in PATH) |
| **Editor Support** | OpenCode only | Any editor with Bash tool |

### When to Use Plugin

- You're using **OpenCode.ai** as your agent platform
- You want **zero-configuration** agent awareness
- You prefer **native tool calls** over Bash executions
- You want automatic **context injection** without relying on AGENTS.md reads

### When to Use Manual CLI

- You're using **Claude Code, Cursor, VS Code, or other editors**
- You want **maximum compatibility** across tools
- You prefer **explicit command visibility** in agent logs
- You want to customize the **exact wording** of rules per project

---

## Migration from Legacy ACTS

If you were using the Python/TypeScript implementation:

### Changes in v1.0.0

| Legacy | New |
|--------|-----|
| `.story/state.json` | `.acts/acts.db` (SQLite) |
| `.acts/lib/*.py` | `acts` binary |
| `.acts/mcp-server/` | Removed (use binary directly) |
| Python scripts | Zig binary (single executable) |
| JSON state edits | `acts state write` command |

### Migration Steps

1. **Backup your `.story/` directory**
2. **Install the new binary** (see Installation)
3. **Migrate state** (if you have existing state.json):
   ```bash
   # Convert JSON to SQLite (one-time)
   cat .story/state.json | acts state write --story <story-id>
   ```
4. **Remove legacy files**:
   ```bash
   rm -rf .acts/lib .acts/mcp-server
   ```
5. **Update AGENTS.md** with new commands
6. **Test**: `acts validate` should pass

### Backwards Compatibility

- `.story/plan.md`, `.story/spec.md`, `.story/sessions/*.md` — **unchanged**
- `.story/state.json` — **deprecated** (removed in v1.0.0, data in SQLite)
- `.acts/acts.json` — **unchanged** (configuration manifest)

---

## Troubleshooting

### Binary not found

```bash
# Check if acts is in PATH
which acts

# If not, add to PATH or use absolute path
export PATH="$PATH:/path/to/acts/binary"
```

### Database locked

SQLite databases can be locked if multiple processes access simultaneously:

```bash
# Check for hanging processes
lsof .acts/acts.db

# SQLite will retry automatically; no action needed in most cases
```

### Gate enforcement not working

Check that triggers are installed:

```bash
sqlite3 .acts/acts.db ".schema trigger"
# Should show enforce_preflight_gate, enforce_task_review_gate, enforce_dependencies
```

If missing: `acts migrate`

### Session validation fails

Required sections in session markdown:
- What was done
- Decisions made
- What was NOT done (and why)
- Approaches tried and rejected
- Open questions
- Current state
- Files touched this session
- Suggested next step
- Agent Compliance

If a section is empty, write "None" rather than omitting it.

---

## Future: MCP Server

A Model Context Protocol (MCP) server is planned for v1.1. This will provide:

- Standardized tool interface across all MCP-enabled clients
- Resource subscriptions for live state updates
- Prompt templates for ACTS operations

Track progress: [GitHub Issues](https://github.com/tommasop/acts-spec/issues)
