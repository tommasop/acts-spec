# ACTS Integration Guide

This guide covers integrating ACTS v2 into different AI-assisted development workflows. Choose the approach that matches your editor/agent setup.

## Approaches Overview

| Approach | Best For | Setup Complexity | Agent Awareness |
|----------|----------|------------------|-----------------|
| **OpenCode Plugin + Skill** | OpenCode.ai users | Low (auto-injected) | Automatic |
| **Manual CLI** | Claude, Cursor, VS Code, other editors | Medium (AGENTS.md) | Manual commands |
| **CBM (cross-repo)** | Multi-repo fleets | Low (MCP + references) | Native MCP tools + `acts graph` |

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
    "./.opencode/plugins/acts.js"
  ],
  "permission": {
    "skill": { "acts": "allow" }
  },
  "mcp": {
    "codebase-memory-mcp": {
      "type": "local",
      "command": ["codebase-memory-mcp"],
      "enabled": true
    }
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
- acts stack create <id> [-t <title>]     Start a new stack (feature branch)
- acts stack status [--json]              Show stack tree + change statuses
- acts stack land                         Merge the whole feature branch once all changes are APPROVED
- acts change add <id> -t <title> [--accept <criteria>]  Add a change (checkpoint on the feature branch)
- acts change status [<id>]               Show change details
- acts verify [<id>] [--all]              Run quality gates; record evidence (GATE for review)
- acts review <id>                        Submit/update the stack's ONE PR (feature vs base; requires verify to pass)
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
| `acts_context` | Load the scoped context pack for a change (auto-resolves from current branch); `blast_radius: true` appends CBM cross-repo trace data |
| `acts_mode` | Control plugin mode: `enter` / `exit` / `status` |
| `acts_zeplin` | Extract an API contract from a Zeplin flow/scenario link for planning |

### Workflow Example

```
User: "Work on change c1 — implement the JWT middleware"

Agent:
1. calls acts_context (or acts "context c1")
   → Receives the context pack (acceptance criteria, preceding changes, notes, files)

2. calls acts "scope c1 src/auth.ts"
   → { "action": "ok" }

3. [Implements code; its commits become c1's checkpoint on the feature branch...]

4. calls acts "verify c1"
   → Records quality-gate evidence; status → VERIFIED

5. calls acts "review c1"
   → Submits/updates the stack's ONE PR (feature → master); status → IN_REVIEW

6. Human reviews on GitHub → calls acts "approve c1"

7. calls acts "stack land"
   → Merges the whole feature branch once all changes are approved; closes the PR
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

**1. Install the binary (globally):**

```bash
curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/master/install.sh | bash -s -- --with-cbm
# or build from source:
cd acts-core && zig build release
./zig-out/bin/acts setup . --bin-dir ~/.local/bin
```

**2. Bootstrap a project (no clone needed):**

```bash
acts setup . --github
# wires .opencode/plugins, the acts skill + slash commands, opencode.json,
# injects AGENTS.md, and (with --github) writes .github/workflows/opencode.yml
```

**3. Add/verify AGENTS.md:**

`acts setup` injects the ACTS v2 section (rules + commands) into `AGENTS.md`. If you prefer to write it by hand, see [docs/templates/agents-minimal.md](templates/agents-minimal.md).

**4. Start a stack:**

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
   → Submits/updates the stack's ONE PR (feature → master)

6. Bash: acts approve c1   (after human review)
7. Bash: acts stack land   (merges the whole feature branch once all changes are approved)
```

### ACTS Mode (Manual)

For non-plugin usage, set ACTS mode via environment variable:

```bash
export ACTS_MODE=on        # Standard (default)
export ACTS_MODE=strict    # Stronger enforcement language in prompts
export ACTS_MODE=off       # Skip ACTS context injection
```

---

## Cross-Repo Memory (codebase-memory-mcp via MCP + acts graph)

ACTS integrates [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) as a **native OpenCode MCP server** (`.opencode/plugins/cbm.js` is gone) for cross-repository code intelligence. It is a single static binary (zero dependencies) that indexes repos into a persistent knowledge graph and exposes 14 tools (search, trace, architecture, impact analysis, Cypher queries, cross-service linking, ADR management).

codebase-memory-mcp gives ACTS:

- **Cross-repo intelligence** — repos indexed into one shared store are linked by `CROSS_*` edges, so a call from `ui-payments` into `magic` is traversable.
- **Token efficiency** — structural graph queries replace thousands of grep/read cycles.
- **158-language parsing** + Hybrid LSP semantic type resolution.
- **Centralized operation** — the binary is installed **once per machine** into `~/.local/bin` / `~/.cache/codebase-memory-mcp`, and the whole fleet shares **one** knowledge graph store at `~/.cache/codebase-memory-mcp`. `acts graph bootstrap` idempotently rebuilds it on CI/fresh machines.

### Configuration

Declare the fleet and the CBM MCP server in `opencode.json`:

```jsonc
{
  "plugin": [
    "./.opencode/plugins/acts.js"
  ],
  "mcp": {
    "codebase-memory-mcp": {
      "type": "local",
      "command": ["codebase-memory-mcp"],
      "enabled": true
    }
  },
  "references": {
    "ui-payments":   { "path": "../ui-payments",         "description": "Payments UI repo" },
    "magic":         { "path": "../ex_magic_library",    "description": "Magic core library" }
  }
}
```

- `plugin` registers ACTS coordination (`acts.js`) only — CBM tools come natively via MCP.
- `mcp.codebase-memory-mcp` exposes CBM's 14 tools directly to the agent (proper schemas, not JSON-string args).
- `references` declares the cross-repo fleet. The shared graph lives at `~/.cache/codebase-memory-mcp`.

### CBM graph tools (via MCP)

`index_repository`, `list_projects`, `delete_project`, `index_status`, `search_graph`, `trace_path`, `detect_changes`, `query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`, `search_code`, `manage_adr`, `ingest_traces`.

### Fleet commands (Zig binary)

| Command | Purpose |
|---------|---------|
| `acts graph repos` | List configured `references` |
| `acts graph index --all` | Index every reference into the shared graph |
| `acts graph bootstrap` | Idempotently install the shared binary + index all refs if the graph is empty (CI / fresh machines) |
| `acts graph span <change_id>` | Map an ACTS change's files to the repos it spans |
| `acts tech-lead <change_id>` | Pre-flight risk report (CBM-grounded) |
| `acts doc-risk <file>` | Evaluate a spec/plan document (static + CBM) |

The `acts.js` plugin injects a `## Cross-Repo Fleet` block into the system context (references + available commands) so the agent sees cross-repo scope at a glance.

### Install

```bash
# Recommended: install acts + cbm globally, then wire the project
acts setup . --github

# Or install cbm manually:
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
```

### Testing

Zig-side tests (`zig build test`) cover the CBM client (`cbm.zig`), doc-risk analysis, and fleet commands. The `acts.js` plugin has an offline test: `npm test` (runs `tests/acts-plugin.test.mjs`).


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

## Architecture Diagrams (archify)

Visualize what a change does to the architecture before review. ACTS renders a change's architecture impact as a self-contained interactive HTML via the [archify](https://github.com/tt-a1i/archify) agent skill (typed JSON IR → validated HTML/SVG).

### Commands

| Command | Purpose |
|---------|---------|
| `acts diagram <id>` | Render an architecture impact map of the components the change touches |
| `acts diagram <id> --delta` | Before/Delta/After comparison (master vs feature branch) |
| `acts diagram <id> --attach` | Post the delta as a comment on the change's PR |
| `acts archify install` | Install the archify renderer skill (`npx skills add tt-a1i/archify`) |
| `acts setup --with-archify` | Wire a project AND install the renderer in one step |

`acts review <id>` auto-attaches the architecture-delta comment (best-effort, non-blocking) once the PR exists and the renderer is installed.

### How it works

1. `acts diagram` reads the change's committed diff (`git diff --name-status base..branch`).
2. Files are grouped into **components** by top-level directory (or configured reference alias for cross-repo paths), typed by directory heuristics (`backend`, `database`, `security`, …).
3. `--delta` emits `base.json` (deleted ∪ modified components) and `head.json` (added ∪ modified components), then runs archify `compare architecture base.json head.json delta.html`.
4. Output lands in `.acts/changes/<id>/archify/*.html` (self-contained, shareable).

### Installation

```bash
acts archify install            # after setup (per-project)
acts archify install --global   # once per machine — every project can render diagrams
# or
acts setup . --with-archify             # wire a project
acts setup . --with-archify --global    # wire a project AND install machine-wide
```

`--global` installs the archify skill to `~/.agents/skills/archify` (auto-loaded by opencode and found by `acts diagram` in any project).

Requires `node` + `npx`. Without the renderer, `acts diagram` degrades to a **textual delta summary** (component | status | kind) and hints at `acts archify install`.

### Plugin tool

`acts_archify` (registered by the OpenCode plugin) runs the renderer directly on a candidate IR JSON:

```json
{ "action": "validate", "type": "architecture", "input": "candidate.json" }
{ "action": "deliver",  "type": "architecture", "input": "candidate.json", "output": "out.html" }
{ "action": "compare",  "type": "architecture", "input": "base.json", "second": "head.json", "output": "delta.html" }
```

Use it to iterate: `validate` → fix per the machine-readable diagnostics → `deliver`.

---

## Minimality (ponytail)

[ponytail](https://github.com/DietrichGebert/ponytail) is a "lazy senior dev" skill — a YAGNI/simplicity ladder that keeps agent code minimal. It is complementary to ACTS checkpoint scoping: the smallest diff keeps a change's range tight and its risk tier low.

### Install

```bash
acts ponytail install          # after setup (per-project)
acts ponytail install --global # once per machine — every project gets /ponytail* + the review checklist
# or
acts setup . --with-ponytail           # wire a project
acts setup . --with-ponytail --global  # wire a project AND install machine-wide
```

`--global` installs into opencode's global config (`~/.config/opencode/{command,plugin,agents}`) and registers the frontmatter plugin in the global `opencode.json`, so every project detects ponytail.

Installs `.agents/rules/ponytail.md`, the `/ponytail*` slash commands, and the frontmatter plugin into the project.

### Project rules (AGENTS.md) — dynamic, per run

`acts ponytail install` also writes an acts-spec runtime plugin (`ponytail-rules.js`, embedded in the `acts` binary). On every turn it resolves the **current** project's `AGENTS.md` (walking up from the session directory; `CLAUDE.md` fallback) and appends a binding precedence directive + path to the system prompt: the project's ruleset is binding and takes precedence over the ponytail ladder — the ladder finds the smallest change *within* the project's constraints (build/lint/test commands, conventions, required checks), never skipping what the project requires.

Because the plugin resolves the rules at run time from the working directory, one global install serves every project without baking anything in. Disable with `PONYTAIL_DEFAULT_MODE=off` (or `~/.config/ponytail/config.json` `{"defaultMode":"off"}`). The injection is idempotent (appears once per session).

### Review integration

When ponytail is installed, `acts review` appends a **minimality checklist** to the stack's one PR:

- YAGNI — does this need to be built at all?
- Reuses existing helpers / stdlib / installed deps
- Shortest working diff; deletions over additions; fewest files
- No new dependency unless unavoidable
- Non-trivial logic leaves ONE runnable check behind

plus a per-change diff-stat table. Use `/ponytail-review` (installed by the skill) to audit a change's diff during review.

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

### `acts diagram` prints only a textual summary

The archify renderer is not installed. Install it:

```bash
acts archify install
# or
acts setup . --with-archify
```

Requires `node`/`npx`. The renderer is looked up in `.opencode/skills/archify`, `.agents/skills/archify`, `~/.config/opencode/skills/archify`, `~/.agents/skills/archify`, and `~/.claude/skills/archify`.

---

## Migration from Legacy ACTS

See [docs/MIGRATION.md](MIGRATION.md) for importing a v1 SQLite story into a v3 stack.

Track progress: [GitHub Issues](https://github.com/tommasop/acts-spec/issues)
