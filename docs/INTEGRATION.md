# ACTS Integration Guide

This guide covers integrating ACTS v2 into different AI-assisted development workflows. Choose the approach that matches your editor/agent setup.

## Approaches Overview

| Approach | Best For | Setup Complexity | Agent Awareness |
|----------|----------|------------------|-----------------|
| **OpenCode Plugin + Skill** | OpenCode.ai users | Low (auto-injected) | Automatic |
| **Manual CLI** | Claude, Cursor, VS Code, other editors | Medium (AGENTS.md) | Manual commands |
| **cbm plugin (cross-repo)** | Multi-repo fleets | Low (plugin + references) | Tool-based (native + `acts_memory`) |

---

## OpenCode Plugin (Recommended)

The OpenCode plugin injects ACTS v2 context automatically and exposes native tools. A superpowers-style skill (`acts`) teaches the agent the workflow.

### How It Works

```
User Message
    |
    v
[Plugin: experimental.chat.messages.transform]
    |
    +-- Injects ACTS v2 bootstrap into first message
    |
    v
[Agent receives context + rules]
    |
    v
[Plugin: tools registration]
    |
    +-- Registers acts, acts_context, acts_mode, acts_zeplin
    |
    v
[Agent calls a tool]
    +-- Plugin executes the acts binary
    +-- Returns output
```

### Installation

**1. Install the binary:**

```bash
# Option A: Copy to project
mkdir -p .acts/bin
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
    "./.opencode/plugins/acts.js",
    "./.opencode/plugins/cbm.js"
  ],
  "permission": {
    "skill": { "acts": "allow" }
  }
}
```

The `acts` skill lives in `.opencode/skills/acts/SKILL.md` and auto-activates.

**3. Restart OpenCode.**

### What the Agent Sees

On the first message of every conversation, the agent receives an ACTS v2 bootstrap:

```
<EXTREMELY_IMPORTANT>
This project uses ACTS v2 (Agent Collaborative Tracking Standard) — a git-native coordination protocol.

Rules:
- Agent MUST load context before writing code: acts context <change>
- Agent MUST NOT submit a change for review until acts verify <change> passes.
- Agent MUST record a session note (acts note) and checkpoint (acts checkpoint) before ending a session.
- Agent MUST stay within the change's scope; use acts scope <change> <file> to check ownership.
- Agent MUST get developer approval on the PR before acts approve / acts stack land.
- Agent MUST run acts validate before finishing.

Commands:
- acts stack create <id> [-t <title>]     Start a new stack
- acts stack status [--json]              Show stack tree + change statuses
- acts stack land                         Merge APPROVED changes bottom-up
- acts change add <id> -t <title> [--accept <criteria>]  Add a change
- acts change status [<id>]               Show change details
- acts verify [<id>] [--all]              Run quality gates; record evidence (GATE for review)
- acts review <id>                        Submit stacked PR (requires verify to pass)
- acts approve <id>                       Mark approved after human PR review
- acts rework <id>                        Reopen for rework
- acts context [<id>]                     Emit scoped context pack
- acts note <id> -m <text>                Append a session note
- acts checkpoint <id> -s <summary>       Record a status checkpoint
- acts redirect <id> --accept <criteria>  Update scope mid-flight
- acts scope <id> <file>                  Check file ownership
- acts validate                           Validate manifest + branch consistency
</EXTREMELY_IMPORTANT>
```

### Native Tools

| Tool | Purpose |
|------|---------|
| `acts` | Run any ACTS command (`acts "verify c1"`, `acts "stack status"`) |
| `acts_context` | Load the scoped context pack for a change (auto-resolves from current branch) |
| `acts_mode` | Control plugin mode: `enter` / `exit` / `status` |
| `acts_zeplin` | Extract an API contract from a Zeplin flow/scenario link for planning |

### Workflow Example

```
User: "Work on change c1 — implement the JWT middleware"

Agent:
1. calls acts_context (or acts "context c1")
   → Receives the context pack (acceptance criteria, parent chain, notes, files)

2. calls acts "scope c1 src/auth.ts"
   → { "action": "ok" }

3. [Implements code on the change branch...]

4. calls acts "verify c1"
   → Records quality-gate evidence; status → VERIFIED

5. calls acts "review c1"
   → Pushes branch, submits stacked PR; status → IN_REVIEW

6. Human reviews on GitHub → calls acts "approve c1"

7. calls acts "stack land"
   → Merges approved changes bottom-up
```

### ACTS Mode Control

Use `acts_mode`:

```json
{ "action": "enter", "level": "on" }     // Enter ACTS mode (default)
{ "action": "enter", "level": "strict" } // Strict enforcement language
{ "action": "exit" }                     // Disable context injection
{ "action": "status" }                   // Check current mode
```

Mode state is persisted in `.acts/plugin-state.json`.

### Zeplin Design Links

When a design link is given, extract the API contract before planning:

```
acts_zeplin url="https://app.zeplin.io/project/abc/flow/xyz"
# or
acts_zeplin url="https://app.zeplin.io/project/abc?seid=xyz"
```

This runs `acts-zeplin-contract.mjs` (flow vs scenario auto-detected). Feed the inferred **endpoints + fields** into the change's `--accept` criteria and use the **flow path** to sequence changes. Requires `ZEPLIN_ACCESS_TOKEN` (env or opencode.json `mcp.zeplin.environment`).

### Customization

Edit `.opencode/plugins/acts.js` to customize:
- Bootstrap content (rules, commands)
- Tool schemas
- Binary discovery logic

---

## Manual CLI (Claude, Cursor, VS Code, etc.)

For editors without plugin support, agents interact with ACTS through standard CLI commands.

### Setup

**1. Install the binary:**

```bash
# Build from source
cd acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/
```

**2. Update AGENTS.md:**

Add the ACTS v2 rules + commands (see [docs/templates/agents-minimal.md](templates/agents-minimal.md) for a full template).

**3. Start a stack:**

```bash
acts stack create auth -t "Add user authentication"
acts change add c1 -t "JWT middleware" --accept "token validated on /api/*
unit tests"
```

### Workflow Example

```
User: "Work on change c1 — implement the JWT middleware"

Agent:
1. Bash: acts context c1
   → Receives the context pack

2. Bash: acts scope c1 src/auth.ts
   → { "action": "ok" }

3. [Implements code using Write/Edit tools...]

4. Bash: acts verify c1
   → Verification evidence recorded

5. Bash: acts review c1
   → Submits stacked PR

6. Bash: acts approve c1   (after human review)
7. Bash: acts stack land
```

### ACTS Mode (Manual)

For non-plugin usage, set ACTS mode via environment variable:

```bash
export ACTS_MODE=on        # Standard (default)
export ACTS_MODE=strict    # Stronger enforcement language in prompts
export ACTS_MODE=off       # Skip ACTS context injection
```

---

## Cross-Repo Memory (codebase-memory-mcp plugin)

ACTS integrates [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) as a **dedicated OpenCode plugin** (`.opencode/plugins/cbm.js`) for cross-repository code intelligence — no separate MCP server entry is needed. It is a single static binary (zero dependencies) that indexes repos into a persistent knowledge graph and exposes 14 tools (search, trace, architecture, impact analysis, Cypher queries, cross-service linking, ADR management).

Unlike a hand-rolled ACTS MCP server, codebase-memory-mcp gives ACTS:

- **Cross-repo intelligence** — repos indexed into one shared store are linked by `CROSS_*` edges, so a call from `ui-payments` into `magic` is traversable.
- **Token efficiency** — structural graph queries replace thousands of grep/read cycles.
- **158-language parsing** + Hybrid LSP semantic type resolution.
- **Self-contained delivery** — the `cbm` plugin auto-installs the binary into `.acts/bin/` and registers the tools itself.

### Configuration

Register the plugin and declare the fleet in `opencode.json`:

```jsonc
{
  "plugin": [
    "./.opencode/plugins/acts.js",
    "./.opencode/plugins/cbm.js"
  ],
  "references": {
    "ui-payments":   { "path": "../ui-payments",         "description": "Payments UI repo" },
    "magic":         { "path": "../ex_magic_library",    "description": "Magic core library" }
  }
}
```

- `plugin` registers both ACTS coordination (`acts.js`) and code intelligence (`cbm.js`).
- `references` declares the cross-repo fleet (exposed to the agent via `@alias` and system context).
- The `cbm` plugin sets `CBM_CACHE_DIR=.acts/cbm` (gitignored) when it spawns the binary, so every referenced repo lands in one shared graph. Set `CBM_ALLOWED_ROOT` to the fleet parent dir for untrusted-caller safety.

### Plugin tools

The `cbm` plugin exposes CBM's 14 native tools directly (each takes a JSON `args` string): `index_repository`, `list_projects`, `delete_project`, `index_status`, `search_graph`, `trace_path`, `detect_changes`, `query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`, `search_code`, `manage_adr`, `ingest_traces`.

Plus fleet helpers and the ACTS bridge:

| Tool | Purpose |
|------|---------|
| `cbm_repos` | List configured `references` |
| `cbm_index_all` | Index every referenced repo into the shared graph |
| `cbm_changes` | Map uncommitted diffs to symbols + repos across the fleet (blast radius) |
| `cbm_install` | (Re)download the CBM binary into `.acts/bin/` |
| `acts_memory scope <change_id>` | Map an ACTS v2 change's changed files to the repos it spans |

The plugin also injects a `## Cross-Repo Memory` block into the system context (fleet repos + per-change repo spans) so the agent sees cross-repo scope at a glance.

### Install

```bash
# Automatic on first use, or force it:
cbm_install

# Manual:
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
```

### Testing

The plugin suites ship offline tests: `npm test` (runs `tests/acts-plugin.test.mjs` and `tests/cbm-plugin.test.mjs`, which spin temp projects with dummy binaries and assert tool registration, reference resolution, and the ACTS bridge).

---

## Comparison: Plugin vs Manual

| Feature | OpenCode Plugin | Manual CLI |
|---------|----------------|------------|
| **Setup** | Add 2 lines to opencode.json | Update AGENTS.md, install binary |
| **Agent Awareness** | Automatic injection every session | Depends on agent reading AGENTS.md |
| **Command Interface** | Native tools (acts, acts_context, acts_zeplin) | Bash tool executions |
| **Context Injection** | `acts_context` + system prompt block | Agent must run `acts context` |
| **Editor Support** | OpenCode only | Any editor with Bash tool |
| **ACTS Mode** | `acts_mode enter/exit/status` | `ACTS_MODE` env var |

### When to Use Plugin

- You're using **OpenCode.ai** as your agent platform
- You want **zero-configuration** agent awareness
- You prefer **native tool calls** over Bash executions
- You want automatic **context injection** without relying on AGENTS.md reads

### When to Use Manual CLI

- You're using **Claude Code, Cursor, VS Code, or other editors**
- You want **maximum compatibility** across tools
- You prefer **explicit command visibility** in agent logs

---

## Troubleshooting

### Binary not found

```bash
which acts
# If not, add to PATH or use absolute path
export PATH="$PATH:/path/to/acts/binary"
```

### Review blocked with "VerifyRequired"

A change cannot be reviewed until `acts verify` passes:

```bash
acts verify c1   # fix any failing gates first
acts review c1
```

### Quality gates don't match my project

Configure them explicitly in `.acts/acts.json`:

```json
{
  "quality_gate": {
    "test": "make test",
    "lint": "make lint",
    "typecheck": null,
    "build": "make build"
  }
}
```

Commands with shell metacharacters are run via `sh -c`.

### Manifest invalid

```bash
acts validate   # reports structural problems
```

---

## Migration from Legacy ACTS

See [docs/MIGRATION.md](MIGRATION.md) for importing a v1 SQLite story into a v2 stack.

Track progress: [GitHub Issues](https://github.com/tommasop/acts-spec/issues)
