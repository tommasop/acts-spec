# ACTS MCP Context Engine — Layer 7

**Status**: Specification only. Implementation pending.

This directory will contain the MCP server implementation for the ACTS Layer 7: MCP Context Engine.

## Purpose

An optional MCP server that sits between the filesystem and the AI agent. It understands ACTS's operation lifecycle and delivers context proactively — replacing the static 9-step Context Protocol with operation-aware, attention-optimized context delivery.

## Problems Solved

| # | Problem | Evidence |
|---|---------|----------|
| 1 | Instruction centrifugation | System prompt pushed to periphery after ~50 turns |
| 2 | Tool call residue | Error tracebacks dominate context after ~50 turns |
| 3 | Stale intermediate reasoning | Old decisions compete with new understanding |
| 4 | Memory write corruption | Session summaries become false facts |
| 5 | Goal drift | 35.9% of SWE-bench Pro failures |
| 6 | Context drift | 35.6% of SWE-bench Pro failures |
| 7 | Lost in the middle | Middle context is under-attended |
| 8 | Recursive loops | Agent enters retry loops |
| 9 | Handoff drift | Errors propagate across agents |
| 10 | Hallucinated compliance | Agent fabricates verification claims |

See the full design spec at `docs/superpowers/specs/2026-03-31-acts-layer7-mcp-context-engine-design.md`.

## MCP Surface

### Tools (8)
- `acts_begin_operation` — Start an operation, get pre-assembled context bundle
- `acts_get_context` — Get next context chunk (incremental delivery)
- `acts_record_decision` — Record decision with evidence and authority level
- `acts_verify_state` — Cross-reference claims against actual state
- `acts_update_anchor` — Update context anchor (re-inject constraints)
- `acts_compact_context` — Compact sessions with preservation contract
- `acts_check_ownership` — Check file modification boundaries
- `acts_propagate_learning` — Share rejected approaches across tasks

### Resources (8)
- `acts://story/state` — Parsed state.json
- `acts://story/board` — Task status table
- `acts://story/ownership` — File ownership map
- `acts://task/{id}/context` — Full context bundle
- `acts://task/{id}/anchor` — Live context anchor
- `acts://task/{id}/learnings` — Cross-task rejected approaches
- `acts://session/current` — Live session state
- `acts://gaps` — Detected context gaps

### Prompts (5)
- `acts_preflight` — Preflight operation guide with context pre-loaded
- `acts_task_start` — Implementation guide with scope, ownership, learnings
- `acts_session_summary` — Session recording guide with live verification
- `acts_handoff` — Handoff briefing with deep context pre-assembled
- `acts_story_review` — Review checklist with all ACs and compliance data

## Directory Structure (planned)

```
src/
├── index.ts               # McpServer + StdioServerTransport
├── engine/
│   ├── context-engine.ts  # Operation lifecycle + context assembly
│   ├── compaction.ts      # Session compaction with preservation contract
│   ├── anchor.ts          # Context anchor manager
│   ├── gap-detector.ts    # Detects context gaps between operations
│   └── learning-propagator.ts  # Cross-task learning
├── tools/                 # One file per MCP tool
├── resources/             # One file per MCP resource
├── prompts/               # One file per MCP prompt
└── lib/
    ├── state-reader.ts    # Parse state.json, plan.md, etc.
    ├── session-reader.ts  # Parse session summaries
    ├── git-reader.ts      # git diff, status, log
    └── schema-validator.ts
```

## Dependencies (planned)

- `@modelcontextprotocol/sdk` — Official MCP TypeScript SDK
- `zod` — Runtime validation for tool inputs
- `chokidar` — File watching for resource change notifications

## Activation

Set `mcp_context_engine.enabled: true` in `.acts/acts.json`. The server runs via stdio transport — launched by the MCP client (Claude Code, Cursor, etc.).

## Conformance

Layer 7 is OPTIONAL for all ACTS conformance levels (Basic, Standard, Full).
