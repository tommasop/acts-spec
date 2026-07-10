# acts-spec

## Setup
- Install: `[install command]`
- Dev: `[dev command]`
- Test: `[test command]`

## Code Style
[Project style conventions]

## Testing
[Project testing conventions]

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Agent Framework

This project uses [superpowers](https://github.com/obra/superpowers) for agent workflow skills.

**Required for all agents:**
- Install superpowers plugin for your platform before starting work
- Skills auto-activate: brainstorming, TDD, subagent-driven-development, code review
- ACTS handles multi-developer coordination (state, handoffs, file ownership)
- Superpowers handles single-developer agent quality (TDD, planning, code review, debugging)

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v1.0.0)

### Review Workflow

```bash
# 1. Agent completes implementation
# ... writes code ...

# 2. Agent creates review context with rationale (optional but recommended)
cat > .acts/reviews/T1-context.json << 'EOF'
{
  "version": 1,
  "summary": "Replaced tmux with hunk daemon for cleaner UX",
  "files": [
    {
      "path": "src/main.zig",
      "summary": "Added daemon spawning and session seeding",
      "annotations": [
        {
          "newRange": [354, 397],
          "summary": "Three new daemon management functions",
          "rationale": "spawnHunkDaemon starts the broker, seedHunkSession registers a session, killHunkDaemon cleans up"
        }
      ]
    }
  ]
}
EOF

# 3. Agent launches review (auto-detects context file)
acts review T1
#   → If TTY: opens hunk diff interactively
#   → If no TTY: starts daemon, exports artifact, polls for approval

# 4. Human reviews in hunk, then approves:
acts approve T1

# 5. Agent marks task done
acts task update T1 --status DONE
```

### Conversational Review (non-TTY)

When running in an agent context without a TTY (e.g. OpenCode subagent):

```bash
# Same context file setup as above (optional)

# Agent gathers review data as JSON:
acts gather-review T1

# Agent parses JSON and drives per-file review via chat:
#   - Presents each file with hunk lines
#   - Uses question tool to ask "Approve this file?"
#   - Collects per-file decisions from human

# On full approval:
acts approve T1

# On changes requested:
acts reject T1 --reason "add missing test for login handler"
```

### ACTS Binary Commands
- `acts init <story-id>` — Initialize new ACTS story
- `acts state read` — Read current story state
- `acts state write --story <id>` — Update story state (JSON from stdin)
- `acts task get <task-id>` — Get task details
- `acts task update <id> --status <status>` — Update task status (enforces gates)
- `acts review <task-id>` — Interactive code review with hunk
- `acts gather-review <task-id>` — Emit structured JSON for conversational review (no TUI)
- `acts approve <task-id>` — Approve task-review gate (shorthand)
- `acts reject <task-id>` — Request changes on task-review gate (shorthand)
- `acts gate add --task <id> --type <type> --status <status>` — Add gate checkpoint
- `acts ownership map` — Show file ownership
- `acts scope check --task <id> --file <path>` — Check if file is safe to modify
- `acts validate` — Validate entire ACTS project
- `acts migrate` — Force schema migration

### Agent Configuration
```json
{
  "tool": "Cursor",
  "version": "0.45.0",
  "model": "claude-3.5-sonnet",
  "cost_limit_per_session": 10.00,
  "config_preset": "default-ruleset"
}
```

### OpenCode Plugin
The ACTS OpenCode plugin is installed at `.opencode/plugins/acts.js`.
Add `"./.opencode/plugins/acts.js"` to your `opencode.json` plugin array.

### ACTS Mode (Plugin)

The OpenCode plugin supports three modes:

| Mode | Behavior |
|------|----------|
| `off` | No ACTS context injection. Use when ACTS is not relevant to the conversation. |
| `on` | Full context injection: story state, active tasks, file ownership, approved overrides. |
| `strict` | All of `on` plus enforcement language. Agent MUST follow gate protocol explicitly. |

**Commands:**
- `acts_mode enter [--level strict]` — Activate ACTS mode
- `acts_mode exit` — Deactivate ACTS mode
- `acts_mode status` — Show current mode

**When to use strict mode:**
- Multi-developer projects with concurrent agents
- High-risk changes (production code, infrastructure)
- When gate violations have been observed

### File Override Protocol

Files owned by **DONE** tasks are locked by default. To modify a locked file:

**1. Agent requests override:**
```
acts_override request --file src/locked.ts --task T3 --reason "bugfix: null pointer"
```

**2. Human developer MUST approve:**
```
acts_override approve --override_id ovr-abc123
```
*Or edit `.acts/override-approvals.json` manually.*

**3. Agent verifies approval:**
```
acts_override check --override_id ovr-abc123
```

**Rules:**
- AI agents MUST NEVER approve their own override requests.
- Overrides expire after 24 hours.
- All approvals are logged in `.acts/override-approvals.json` for audit.
- Without approval, the agent MUST NOT modify the file.

### Data Storage
- Structured state (stories, tasks, gates, decisions): SQLite at `.acts/acts.db`
- Narratives: Markdown files
- `.story/state.json`: REMOVED (replaced by SQLite)

---

## Codebase Memory (cross-repo)

ACTS integrates [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) for multi-repository orchestration via the **`cbm` OpenCode plugin** (`.opencode/plugins/cbm.js`) — no separate MCP server required. Multiple repos are declared as OpenCode `references`; the plugin auto-installs the CBM binary into `.acts/bin/` and indexes the fleet into a single per-project knowledge graph (`.acts/cbm/`, gitignored) where `CROSS_*` edges link symbols across repos.

### Setup (in `opencode.json`)
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
The CBM binary is installed automatically on first use (or run `cbm_install`). Manual install: `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`

### cbm plugin tools (native)
The plugin exposes CBM's 14 tools directly, each taking a JSON `args` string:
- `index_repository` — index a repo into the graph
- `list_projects` — indexed projects + node/edge counts
- `search_graph` — structural search by label/name/file/degree
- `trace_path` — BFS call tracing inbound/outbound across repos (`CROSS_*` edges)
- `query_graph` — read-only Cypher-like graph query across the fleet
- `get_architecture` — cross-repo architecture summary
- `detect_changes` — map uncommitted diffs to symbols + repos (blast radius)
- `get_code_snippet`, `get_graph_schema`, `search_code`, `manage_adr`, `ingest_traces`, `delete_project`, `index_status`

### Fleet helpers + ACTS bridge
- `cbm_repos` — list configured `references`
- `cbm_index_all` — index every referenced repo into the shared graph
- `cbm_changes` — detect changes across the fleet (blast radius)
- `cbm_install` — (re)download the CBM binary
- `acts_memory scope <task_id>` — map an ACTS task's `files_touched` to the repos it spans
- `acts_tech_lead_analysis --task_id <id> [--depth 3] [--risk_threshold MEDIUM]` — pre-flight risk report combining ACTS task context with CBM graph intelligence

### Tech Lead Pre-Flight Analysis (`acts_tech_lead_analysis`)

A standalone tool that produces a structured risk report before coding begins. It reads an ACTS task, resolves affected symbols via CBM graph queries, traces call chains with risk classification, and returns a markdown report for LLM interpretation.

**When to use:**
- Before starting implementation on a task with `files_touched`
- During tech lead review to assess cross-repo impact
- When onboarding to unfamiliar code to understand blast radius

**Usage:**
```
acts_tech_lead_analysis --task_id T1
acts_tech_lead_analysis --task_id T1 --depth 2
acts_tech_lead_analysis --task_id T1 --risk_threshold HIGH
```

**Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `task_id` | Yes | — | ACTS task to analyze |
| `depth` | No | `3` | Call chain trace depth (how many hops to follow) |
| `risk_threshold` | No | `MEDIUM` | Minimum risk level to include: CRITICAL, HIGH, MEDIUM, LOW |

**Processing pipeline:**
1. Read ACTS task → extract `files_touched`
2. Map each file → repo (via `opencode.json` references) → CBM project
3. For each file, search for functions: `search_graph --file_path <file> --label Function`
4. For each function, trace call chains: `trace_path --direction both --risk-labels true --mode cross_service`
5. Classify risk per symbol:
   - **CRITICAL**: Cross-repo HTTP/GRPC edge, OR callers ≥ 2 in other repos
   - **HIGH**: ≥ 5 callers/callees, OR complexity > 15
   - **MEDIUM**: ≥ 3 callers/callees, OR complexity > 8
   - **LOW**: Everything else
6. Detect blast radius via `detect_changes`
7. Return structured markdown report

**Output sections:**
- **Risk Summary** — counts per risk level
- **Cross-Repo Impact** — symbols calling/called by other repos (if any)
- **Per-File Analysis** — table of symbols with risk, caller/callee counts, complexity
- **Blast Radius** — changed files and impacted symbols from git diff
- **Warnings** — indexing or query errors

**Example output:**
```markdown
# Tech Lead Pre-Flight Report: T1

**Task:** Add payment retry logic
**Status:** IN_PROGRESS
**Files:** 3 | **Symbols:** 15 | **Depth:** 3

## Risk Summary
| Level | Count |
|-------|-------|
| CRITICAL | 1 |
| HIGH | 4 |
| MEDIUM | 6 |
| LOW | 4 |

## Cross-Repo Impact
🔴 **CRITICAL** `magic.PaymentService.create` → `retry_payment`
   Edge: OUTBOUND

## Per-File Analysis

### lib/payment/retry.ex (magic)
| Symbol | Risk | Callers | Callees | Cross-Repo | Complexity |
|--------|------|---------|---------|------------|------------|
| retry_payment | HIGH | 3 | 2 | 1 outgoing | 12 |
| handle_timeout | MEDIUM | 1 | 1 | — | 6 |
```

**Interpreting the report:**
- Cross-repo impacts require deployment coordination
- HIGH-risk symbols with many callers need backward compatibility checks
- HIGH-complexity functions may warrant code review
- Use the data to prioritize review and testing

### Slash Commands

Custom OpenCode commands for quick access:

| Command | Description |
|---------|-------------|
| `/tech-lead <task_id>` | Run pre-flight risk analysis on a task |
| `/risk <task_id>` | Short alias for `/tech-lead` |

**Usage:**
```
/tech-lead T1
/risk T1
```

If no task ID is provided, the command will list active tasks and ask which to analyze.

### Cross-Repo Workflow
1. Declare the fleet as `references` in `opencode.json` (plugin already registered).
2. `acts mode enter`, then `cbm_index_all` (or `cbm_install` first) to build the shared graph.
3. `acts init <story>` and create per-repo tasks (their `files_touched` map to repos automatically).
4. Use `acts_memory scope <task>`, `trace_path`, `query_graph`, `cbm_changes` for cross-repo impact analysis.

### Testing
The `cbm` plugin is covered by an offline test: `npm test` (runs `tests/cbm-plugin.test.mjs`, which spins a temp project with dummy `acts` + `codebase-memory-mcp` binaries and asserts tool registration, reference resolution, `cbm_index_all` wiring, and the `acts_memory scope` bridge).



### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
