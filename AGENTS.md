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

This project uses ACTS v2 — a **git-native coordination protocol** for agent-aided development. Git is the system of record: a *stack* is a feature (a **feature branch** off `master`), a *change* is one unit of agent work (**a checkpoint on that branch**). Verification is the gate; context is served on demand.

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
- `acts stack create <id> [-t <title>]` — Start a new stack (feature branch + manifest)
- `acts stack status [--json]` — Show stack tree + change statuses
- `acts stack land` — Merge the whole feature branch once all changes are APPROVED
- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change (checkpoint on the feature branch)
- `acts change status [<id>]` — Show change details
- `acts verify [<id>] [--all]` — Run quality gates; record evidence (GATE for review)
- `acts review <id>` — Submit/update the stack's ONE PR (feature vs base; requires verify to pass)
- `acts approve <id>` — Mark approved after human PR review
- `acts rework <id>` — Reopen for rework (clears approval)
- `acts context [<id>]` — Emit scoped context pack (durable task state)
- `acts note <id> -m <text>` — Append a session note
- `acts checkpoint <id> -s <summary>` — Record a status checkpoint
- `acts redirect <id> --accept <criteria>` — Update scope mid-flight without context loss
- `acts scope <id> <file>` — Check file ownership (derived from diffs)
- `acts diagram <id> [--delta] [--attach]` — Render the change's architecture impact via archify (HTML; `--attach` comments on the PR)
- `acts archify install` — Install the archify diagram renderer skill (`npx skills add tt-a1i/archify`)
- `acts migrate [<story-id>]` — Import a v1 SQLite story into a v2 stack (reads `.acts/acts.db` via `sqlite3`)
- `acts validate` — Validate manifest + branch consistency

Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED

### Review Workflow
1. Agent implements on the stack's feature branch (change loaded via `acts context`); its commits become the change's checkpoint range.
2. `acts verify <change>` runs quality gates; a change CANNOT be reviewed until verify passes.
3. `acts review <change>` submits/updates the stack's ONE PR (via `gh`), body = rationale + verification evidence + acceptance criteria.
4. Human reviews on GitHub PR UI → `acts approve <change>`.
5. `acts stack land` merges the whole feature branch once all changes are approved, then closes the PR.
6. Agent records `acts note` + `acts checkpoint`, then `acts validate`.

### Design Links (Zeplin)
When a Zeplin link is given, extract the API contract before planning:
- `acts_zeplin <url>` (plugin tool) or `node acts-zeplin-contract.mjs --flow <url>` / `--scenario <url>`
- Feed inferred endpoints + fields into change `--accept` criteria; sequence changes along the flow path.
- Requires `ZEPLIN_ACCESS_TOKEN` (env or opencode.json `mcp.zeplin.environment`).

### Data Storage
- Coordination state: `.acts/stack.json` (git-committed manifest, diffable) — a change = a checkpoint (commit range `start_sha..end_sha`) on the stack's feature branch; one PR per stack
- Code truth: the stack's feature branch + its ONE PR (no sidecar database)
- Session notes: `.acts/changes/<id>/notes/*.md`
- Cross-repo knowledge graph: `.acts/cbm/` (gitignored)

---

## Codebase Memory (cross-repo)

ACTS integrates [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) for multi-repository orchestration. CBM is exposed as a **native OpenCode MCP server** and driven from the Zig binary via `acts graph` / `acts tech-lead` / `acts doc-risk`. Multiple repos are declared as OpenCode `references`; the fleet indexes into a single shared knowledge graph (`~/.cache/codebase-memory-mcp`, gitignored) where `CROSS_*` edges link symbols across repos.

### Setup (in `opencode.json`)
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
CBM is exposed as a **native OpenCode MCP server** (no plugin needed) — its 14 graph tools (`search_graph`, `trace_path`, `query_graph`, `get_architecture`, `detect_changes`, …) are available to the agent directly. `acts setup` wires this entry. Install the binary with `acts setup --with-cbm` (or `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`).

### CBM graph tools (via MCP)
- `index_repository` — index a repo into the graph
- `list_projects` — indexed projects + node/edge counts
- `search_graph` — structural search by label/name/file/degree
- `trace_path` — BFS call tracing inbound/outbound across repos (`CROSS_*` edges)
- `query_graph` — read-only Cypher-like graph query across the fleet
- `get_architecture` — cross-repo architecture summary
- `detect_changes` — map uncommitted diffs to symbols + repos (blast radius)
- `get_code_snippet`, `get_graph_schema`, `search_code`, `manage_adr`, `ingest_traces`, `delete_project`, `index_status`

### Fleet commands (Zig binary, replaces the old cbm plugin)
- `acts graph repos` — list configured `references`
- `acts graph index --all` — index every reference into the shared graph
- `acts graph bootstrap` — idempotent install+index (CI / fresh machines)
- `acts graph span <change_id>` — map a change's files to the repos it spans
- `acts tech-lead <change_id>` — pre-flight risk report combining change context with CBM graph intelligence
- `acts doc-risk <file>` — evaluate a spec/plan document (static + CBM)

### Tech Lead Pre-Flight Analysis (`acts tech-lead`)

Produces a structured risk report before coding begins. It reads an ACTS change, resolves affected symbols via CBM graph queries, traces call chains with risk classification, and returns a markdown report for LLM interpretation.

**When to use:**
- Before starting implementation on a change
- During tech lead review to assess cross-repo impact
- When onboarding to unfamiliar code to understand blast radius

**Usage:**
```
acts tech-lead c1
```

**Processing pipeline:**
1. Read ACTS change → extract its changed files (git diff vs base)
2. Map each file → repo (via `opencode.json` references) → CBM project
3. For each file, search for functions: `search_graph --project <p> --name-pattern .* --label Function`
4. For each function, trace call chains: `trace_path --mode cross_service`
5. Classify risk per symbol:
   - **CRITICAL**: cross-repo edges, OR callers ≥ 2 in other repos
   - **HIGH**: ≥ 5 callers/callees, OR complexity > 15
   - **MEDIUM**: ≥ 3 callers/callees, OR complexity > 8
   - **LOW**: Everything else
6. Return structured markdown report

### Doc Risk (`acts doc-risk`)

Evaluate a spec or plan document (local `.md`/`.txt` or a URL) and highlight the major painpoints, grounded in the codebase via CBM:

```
acts doc-risk plan.md
acts doc-risk https://example.com/spec.md --out report.md
```

The report combines:
- **Static signals** — ambiguity, scope, tech-debt/migration, integration, concurrency, security, testability
- **Code-intelligence (CBM graph)** — resolves code references in the document to real symbols, reporting complexity, cross-repo edges, and hotspots
- **Major painpoints** — ranked lines from the document flagged for risk or ambiguity

### Slash Commands

| Command | Description |
|---------|-------------|
| `/tech-lead <change_id>` | Run `acts tech-lead` pre-flight risk analysis |
| `/risk <change_id>` | Short alias for `/tech-lead` |
| `/doc-risk <file>` | Run `acts doc-risk` on a spec/plan |
| `/graph <sub> [args]` | `acts graph` fleet helpers |

**Usage:**
```
/tech-lead c1
/doc-risk plan.md
```

If no change ID is provided, the command will list active changes and ask which to analyze.

### Cross-Repo Workflow
1. Declare the fleet as `references` in `opencode.json` (CBM exposed via MCP).
2. `acts setup .`, then `acts graph bootstrap` (or `acts graph index --all`) to build the shared graph.
3. `acts stack create <id>` and add changes (`acts change add`) whose changed files map to repos automatically.
4. Use `acts graph span <change>`, `trace_path`, `query_graph` for cross-repo impact analysis.

### Testing
The `acts.js` plugin is covered by an offline test: `npm test` (runs `tests/acts-plugin.test.mjs`). Zig-side tests (`zig build test`) cover the CBM client, doc-risk analysis, and fleet commands.




### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
