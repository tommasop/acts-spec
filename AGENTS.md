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

## ACTS Integration (v2)

This project uses ACTS v2 — a **git-native coordination protocol** for agent-aided development. Git is the system of record: a *stack* is a feature (base branch), a *change* is one unit of agent work (a stacked branch + PR). Verification is the gate; context is served on demand.

### Agent Framework

This project uses [superpowers](https://github.com/obra/superpowers) for agent workflow skills.

- Install superpowers plugin for your platform before starting work
- Skills auto-activate: brainstorming, TDD, subagent-driven-development, code review, acts
- ACTS handles coordination (branch stacks, verification gates, durable context, PR review, cross-repo impact)
- Superpowers handles single-developer agent quality (TDD, planning, code review, debugging)

### Rules
- Agent MUST load context before writing code: `acts context <change>`
- Agent MUST NOT submit a change for review until `acts verify <change>` passes
- Agent MUST record a session note + checkpoint before ending: `acts note` / `acts checkpoint`
- Agent MUST stay within the change's scope: `acts scope <change> <file>`
- Agent MUST get developer approval on the PR before `acts approve` / `acts stack land`
- Agent MUST run `acts validate` before finishing

### ACTS v2 Commands
- `acts stack create <id> [-t <title>]` — Start a new stack (base branch + manifest)
- `acts stack status [--json]` — Show stack tree + change statuses
- `acts stack land` — Merge APPROVED changes bottom-up
- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change on top of the stack
- `acts change status [<id>]` — Show change details
- `acts verify [<id>] [--all]` — Run quality gates; record evidence (GATE for review)
- `acts review <id>` — Submit stacked PR (requires verify to pass)
- `acts approve <id>` — Mark approved after human PR review
- `acts rework <id>` — Reopen for rework (clears approval)
- `acts context [<id>]` — Emit scoped context pack (durable task state)
- `acts note <id> -m <text>` — Append a session note
- `acts checkpoint <id> -s <summary>` — Record a status checkpoint
- `acts redirect <id> --accept <criteria>` — Update scope mid-flight without context loss
- `acts scope <id> <file>` — Check file ownership (derived from diffs)
- `acts migrate [<story-id>]` — Import a v1 SQLite story into a v2 stack (reads `.acts/acts.db` via `sqlite3`)
- `acts validate` — Validate manifest + branch consistency

Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED

### Review Workflow
1. Agent implements on the change branch (loaded via `acts context`).
2. `acts verify <change>` runs quality gates; a change CANNOT be reviewed until verify passes.
3. `acts review <change>` submits a stacked PR (via `gh`), body = rationale + verification evidence + acceptance criteria.
4. Human reviews on GitHub PR UI → `acts approve <change>`.
5. `acts stack land` merges approved changes bottom-up.
6. Agent records `acts note` + `acts checkpoint`, then `acts validate`.

### Design Links (Zeplin)
When a Zeplin link is given, extract the API contract before planning:
- `acts_zeplin <url>` (plugin tool) or `node acts-zeplin-contract.mjs --flow <url>` / `--scenario <url>`
- Feed inferred endpoints + fields into change `--accept` criteria; sequence changes along the flow path.
- Requires `ZEPLIN_ACCESS_TOKEN` (env or opencode.json `mcp.zeplin.environment`).

### Data Storage
- Coordination state: `.acts/stack.json` (git-committed manifest, diffable)
- Code truth: git branches/PRs (no sidecar database)
- Session notes: `.acts/changes/<id>/notes/*.md`
- Cross-repo knowledge graph: `.acts/cbm/` (gitignored)

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
- `acts_memory scope <change_id>` — map an ACTS change's changed files to the repos it spans
- `acts_tech_lead_analysis --change_id <id> [--depth 3] [--risk_threshold MEDIUM]` — pre-flight risk report combining ACTS change context with CBM graph intelligence

### Tech Lead Pre-Flight Analysis (`acts_tech_lead_analysis`)

A standalone tool that produces a structured risk report before coding begins. It reads an ACTS change, resolves affected symbols via CBM graph queries, traces call chains with risk classification, and returns a markdown report for LLM interpretation.

**When to use:**
- Before starting implementation on a change
- During tech lead review to assess cross-repo impact
- When onboarding to unfamiliar code to understand blast radius

**Usage:**
```
acts_tech_lead_analysis --change_id c1
acts_tech_lead_analysis --change_id c1 --depth 2
acts_tech_lead_analysis --change_id c1 --risk_threshold HIGH
```

**Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `change_id` | Yes | — | ACTS change to analyze |
| `depth` | No | `3` | Call chain trace depth (how many hops to follow) |
| `risk_threshold` | No | `MEDIUM` | Minimum risk level to include: CRITICAL, HIGH, MEDIUM, LOW |

**Processing pipeline:**
1. Read ACTS change → extract its changed files (git diff vs base)
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
| `/tech-lead <change_id>` | Run pre-flight risk analysis on a change |
| `/risk <change_id>` | Short alias for `/tech-lead` |

**Usage:**
```
/tech-lead c1
/risk c1
```

If no change ID is provided, the command will list active changes and ask which to analyze.

### Cross-Repo Workflow
1. Declare the fleet as `references` in `opencode.json` (plugin already registered).
2. `acts setup .`, then `cbm_index_all` (or `cbm_install` first) to build the shared graph.
3. `acts stack create <id>` and add changes (`acts change add`) whose changed files map to repos automatically.
4. Use `acts_memory scope <change>`, `trace_path`, `query_graph`, `cbm_changes` for cross-repo impact analysis.

### Testing
The `cbm` plugin is covered by an offline test: `npm test` (runs `tests/cbm-plugin.test.mjs`, which spins a temp project with dummy `acts` + `codebase-memory-mcp` binaries and asserts tool registration, reference resolution, `cbm_index_all` wiring, and the `acts_memory scope` bridge).



### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
