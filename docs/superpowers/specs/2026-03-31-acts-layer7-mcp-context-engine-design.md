# Layer 7: MCP Context Engine — Design Spec

**Date**: 2026-03-31
**Status**: Approved
**ACTS Version**: 0.5.0 (proposed)
**Layer**: 7 (OPTIONAL for all conformance levels)

---

## Problem Statement

ACTS's Context Protocol (§5.2) defines a static 9-step reading order with a token budget. This approach has 10 well-documented failure modes that affect AI agent workflows at scale:

| # | Problem | Evidence | ACTS Impact |
|---|---------|----------|-------------|
| 1 | Instruction centrifugation | System prompt pushed to periphery after ~50 turns. Larger context windows make it worse (Arize production analysis, Jan 2026) | AGENTS.md rules forgotten mid-session |
| 2 | Tool call residue | Error tracebacks, file reads dominate context after ~50 turns. Agent reasons over its own failure history (SWE-bench Pro research) | Preflight context degrades during long task-start |
| 3 | Stale intermediate reasoning | Chain-of-thought from turn 10 conflicts with understanding at turn 60. No "superseded" marker. 17% of Claude Sonnet 4 failures (SWE-bench Pro) | Old decisions from early sessions compete with new understanding |
| 4 | Memory write corruption | What agent writes to memory at turn 20 (incomplete info) becomes ground truth at turn 80 (Prassanna Ravishankar, agent drift research, Feb 2026) | Session summaries become false facts for next developer |
| 5 | Goal drift | 35.9% of failures: syntactically valid code that misses the actual task (SWE-bench Pro failure analysis) | Agent implements wrong acceptance criteria |
| 6 | Context drift | 35.6% of failures: accumulated logs exceed effective context management (SWE-bench Pro) | Long task-start sessions lose track of scope |
| 7 | Lost in the middle | Content in middle of long contexts is effectively ignored by attention (Lost in the Middle, Liu et al.) | Context Protocol steps 6-9 are under-attended |
| 8 | Recursive loops | Agent enters polling/retry loops, burning tokens without progress (Arize production analysis) | Agent re-reads files repeatedly instead of proceeding |
| 9 | Multi-agent handoff drift | Agent A's summary becomes agent B's starting context. Errors propagate as fact (coordination drift research) | Handoff briefing inherits prior agent's drift |
| 10 | Hallucinated compliance | Agent fabricates tool arguments and compliance claims (Arize, OpenAI hallucination research) | Session summary claims are unverifiable |

After ~50 turns of tool calls, error tracebacks, and file reads, the agent's original instructions are technically still in the context window but effectively ignored by the attention mechanism. SWE-bench Pro shows agents drop from ~80% on short tasks to ~23% on long-horizon tasks. On real-world tool-use benchmarks (MCP Atlas), success rates top out at 40-60% regardless of model family.

---

## Design

### Architecture

An MCP server at `.acts/mcp-server/` that sits between the filesystem and the AI agent. It understands ACTS's operation lifecycle and delivers context proactively — replacing the static 9-step Context Protocol with operation-aware, attention-optimized context delivery.

```
┌─────────────────────────────────────────────────────┐
│  AI Agent (Cursor, Claude Code, etc.)               │
│                                                     │
│  Reads: AGENTS.md, .story/state.json (bootstrap)    │
│  Then: delegates context to MCP server              │
├─────────────────────────────────────────────────────┤
│  ACTS MCP Server (.acts/mcp-server/)                │
│                                                     │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │  Tools   │ │ Resources │ │     Prompts        │  │
│  │(mutation)│ │  (state)  │ │(operation guides)  │  │
│  └──────────┘ └───────────┘ └────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │         Context Engine (internal)            │   │
│  │  - Operation lifecycle tracker               │   │
│  │  - Context assembler                         │   │
│  │  - Anchor manager                            │   │
│  │  - Gap detector                              │   │
│  │  - Compaction engine                         │   │
│  │  - Learning propagator                       │   │
│  └──────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────┤
│  .story/ (filesystem — source of truth)             │
│  .acts/  (schemas, operations — source of truth)    │
│  AGENTS.md (constitution — source of truth)         │
└─────────────────────────────────────────────────────┘
```

**Critical constraint**: The MCP server does NOT replace the file-based system. Files remain the source of truth. The server reads/writes them — never overrides them. An agent that doesn't use the MCP server must still work correctly using the existing 9-step Context Protocol.

### Placement in the Stack

```
Layer 7: MCP CONTEXT ENGINE   (OPTIONAL)
Layer 6: CODE REVIEW           (REQUIRED v0.4+)
Layer 5: ADAPTERS              (community)
Layer 4: COMMUNICATION
Layer 3: OPERATIONS
Layer 2: STATE
Layer 1: CONSTITUTION
```

Layer 7 is optional for all conformance levels (Basic, Standard, Full).

---

## MCP Capabilities

### Tools (8 tools)

#### `acts_begin_operation`

Start an ACTS operation. Server loads all context for this operation type and returns a ready-to-use bundle.

**Input**:
```json
{
  "operation": "preflight | task-start | session-summary | handoff | story-review",
  "task_id": "T3",
  "developer": "alice"
}
```

**Output**: Context bundle with all relevant state pre-assembled. Agent receives everything it needs without reading files.

**Problems solved**: #1 (instruction centrifugation), #5 (goal drift), #6 (context drift), #7 (lost in the middle)

#### `acts_get_context`

Get the next chunk of context during an operation. Server tracks what was already delivered and what's needed next.

**Input**:
```json
{
  "task_id": "T3",
  "step": "dependency_interfaces | sessions | ownership",
  "budget_remaining": 15800
}
```

**Output**: Next priority context chunk, formatted compactly. Includes budget tracking.

**Problems solved**: #1, #2 (tool call residue), #7

#### `acts_record_decision`

Record a decision, deviation, or rejected approach with structured metadata. Prevents stale reasoning by marking decisions as authoritative.

**Input**:
```json
{
  "task_id": "T3",
  "topic": "form_library",
  "plan_said": "Formik",
  "decided": "React Hook Form",
  "reason": "Formik incompatible with our validation pattern",
  "evidence": "src/components/TwoFactorSetup.tsx:12 — imports react-hook-form",
  "authority": "developer_approved | agent_decided",
  "tags": ["frontend", "forms"]
}
```

**Output**: Confirmation + updated `decisions.json`

**Problems solved**: #3 (stale reasoning), #4 (memory corruption)

#### `acts_verify_state`

Cross-reference agent claims against actual filesystem/git state.

**Input**:
```json
{
  "session_file": "20260328-180000-alice.md",
  "run_commands": true
}
```

**Output**:
```json
{
  "verified": {
    "files_touched": { "match": true, "expected": 3, "actual": 3 },
    "compiles": { "match": true, "claimed": true, "actual": true },
    "tests_pass": { "match": false, "claimed": true, "actual": "2/12 failing" },
    "agents_md_read": { "match": "partial", "sections_quoted": ["Rules"], "sections_missing": ["Forbidden"] }
  },
  "corrupted_fields": ["tests_pass"],
  "recommendation": "Session summary claims tests pass but 2/12 are failing."
}
```

**Problems solved**: #4 (memory corruption), #10 (hallucinated compliance)

#### `acts_update_anchor`

Update context anchor with current task state. Re-injects critical constraints at the end of context.

**Input**:
```json
{
  "task_id": "T3",
  "goal": "Build 2FA setup UI component",
  "not_goal": ["Backend TOTP endpoint (T1)", "Login enforcement (T5)"],
  "constraints": ["Don't modify T1 files", "strict TypeScript"],
  "turn_count": 47
}
```

**Output**: Updated anchor resource at `acts://task/T3/anchor`

**Problems solved**: #1 (instruction centrifugation), #5 (goal drift)

#### `acts_compact_context`

Compact older session context using preservation contract.

**Input**:
```json
{
  "task_id": "T3",
  "keep_latest": 2
}
```

**Output**: Compacted sessions summary. Preserves decisions, rejected approaches, open questions. Discards tool call residue.

**Problems solved**: #2 (tool call residue), #3 (stale reasoning)

#### `acts_check_ownership`

Check if file modification crosses task boundaries.

**Input**:
```json
{
  "file_path": "src/routes/totp.ts",
  "task_id": "T3"
}
```

**Output**:
```json
{
  "owned_by": "T1",
  "status": "DONE",
  "action": "warn",
  "message": "This file is owned by completed task T1. Modifications may violate isolation. Proceed only with developer approval."
}
```

**Problems solved**: #5 (goal drift), #6 (context drift)

#### `acts_propagate_learning`

Share rejected approach from one task to related tasks.

**Input**:
```json
{
  "source_task": "T1",
  "approach": "Use qrcode npm package",
  "reason": "Generated blurry QR codes at high DPI",
  "tags": ["qr", "frontend", "image_quality"]
}
```

**Output**: Stored in `decisions.json`, surfaced in future context bundles for related tasks.

**Problems solved**: #9 (handoff drift)

---

### Resources (8 resources)

| Resource | URI | Content | Updates When |
|----------|-----|---------|--------------|
| Story State | `acts://story/state` | Parsed, validated state.json | Any state change |
| Story Board | `acts://story/board` | Computed task status table | Task status changes |
| Ownership Map | `acts://story/ownership` | Files owned by completed tasks | files_touched changes |
| Task Context | `acts://task/{id}/context` | Full context bundle for current operation | Context ingestion completes |
| Task Anchor | `acts://task/{id}/anchor` | Compact structured summary (live) | Anchor updates |
| Task Learnings | `acts://task/{id}/learnings` | Rejected approaches from ALL tasks | Any session records a rejection |
| Session Current | `acts://session/current` | Live session state (build, test, git) | During task-start |
| Gaps | `acts://gaps` | Detected context gaps for current operation | Operation transitions |

Resources use MCP's subscribe/notification mechanism. When state.json changes, the server sends `notifications/resources/updated` to subscribed clients.

---

### Prompts (5 prompts)

Each prompt pre-loads all context the agent needs for that operation. The agent doesn't read files — the server delivers everything.

#### `acts_preflight`

**Parameters**: `task_id`, `developer`

**Embedded resources**: `acts://story/state`, `acts://story/board`, `acts://story/ownership`, `acts://task/{id}/anchor`, `acts://task/{id}/learnings`

**Guides**: Validate story/task status, present Story Board and Ownership Map, wait for developer approval gate, update state.json.

#### `acts_task_start`

**Parameters**: `task_id`

**Embedded resources**: `acts://task/{id}/context` (full bundle), `acts://task/{id}/anchor` (refreshed)

**Guides**: Implement with TDD, record decisions, update anchor every 15 turns, check ownership before file modifications, anti-loop guidance.

#### `acts_session_summary`

**Parameters**: `developer`

**Embedded resources**: `acts://story/state`, `acts://session/current` (live build/test/git)

**Guides**: Record what was done/not done, run live verification commands, record agent compliance with evidence, update decisions.json.

#### `acts_handoff`

**Parameters**: `task_id`, `new_developer`

**Embedded resources**: All preflight resources + `acts://task/{id}/learnings` (ALL tasks) + ALL session summaries for the task

**Guides**: Synthesize comprehensive briefing, highlight pitfalls from rejected approaches, surface open questions, reassign in state.json.

#### `acts_story_review`

**Parameters**: (none)

**Embedded resources**: `acts://story/state`, spec.md acceptance criteria, all session summaries, AGENTS.md compliance rules

**Guides**: Verify each acceptance criterion, audit agent compliance across all sessions, generate PR description, update state.json to REVIEW.

---

## Context Engine — Internal Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Context Engine                    │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  Operation   │  │   Context    │  │  Anchor   │  │
│  │  Lifecycle   │──│  Assembler   │──│  Manager  │  │
│  │  Tracker     │  │              │  │           │  │
│  └─────────────┘  └──────────────┘  └───────────┘  │
│        │                │                 │         │
│  ┌─────┴──────┐  ┌──────┴───────┐  ┌──────┴──────┐ │
│  │  Gap       │  │  Compaction  │  │  Learning   │ │
│  │  Detector  │  │  Engine      │  │  Propagator │ │
│  └────────────┘  └──────────────┘  └─────────────┘ │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │              State Reader                    │   │
│  │  (state.json, plan.md, sessions, decisions)  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Operation Lifecycle Tracker**: Knows which operation is active, what context it needs, what's been delivered, and what comes next.

**Context Assembler**: Builds context bundles by reading from State Reader, applying decisions/rejections, reordering for attention optimization, and tracking budget. Delivers context in reverse priority order (critical items last) to exploit transformer recency bias.

**Anchor Manager**: Maintains the live anchor resource. Initialized at preflight, refreshed at task updates, frozen at session-summary.

**Gap Detector**: Compares what context was consumed vs what decisions were made. Flags gaps (e.g., "agent never read dependency interfaces but modified a dependency file").

**Compaction Engine**: Applies the preservation contract — keeps decisions, rejected approaches, open questions; discards tool call residue, verbose explorations.

**Learning Propagator**: Tags rejected approaches with semantic categories and surfaces relevant learnings from other tasks during context assembly.

**State Reader**: Parses and validates all ACTS files (state.json, plan.md, sessions, decisions.json). Caches reads to avoid redundant file I/O.

---

## Attention Optimization

The context engine delivers content in reverse priority order to exploit transformer recency bias:

```
[last]  ← Agent generates here (maximum attention)
  Anchor: goal, constraints, ownership
  Current task: plan entry + decisions override
  Dependency interfaces (if relevant to current step)
  Rejected approaches from other tasks (if relevant)
  Session summaries (latest only, compacted)
  Historical context (older sessions, other tasks)
[first] ← Minimum attention
```

This inverts the Context Protocol's 1→9 order. Critical information (constraints, goal, ownership) is always last. Historical context (sessions, dependencies) is first.

---

## Loop Detection

The server tracks tool call patterns. If the agent calls `acts_get_context` with identical parameters 3+ times consecutively, the server returns a loop warning:

```json
{
  "warning": "loop_detected",
  "pattern": "acts_get_context called 3 times with identical parameters for task T3",
  "suggestion": "You already have this context. Proceed with implementation or ask the developer."
}
```

Additionally, the server tracks `turn_count` per operation. If it exceeds a threshold (configurable, default 80), the server suggests compaction or context refresh.

---

## State Extensions

### New file: `.story/decisions.json`

Story-scoped file for structured decisions, rejected approaches, and open questions. Server-managed, schema-validated.

```json
{
  "decisions": [
    {
      "task_id": "T3",
      "timestamp": "2026-03-28T16:00:00Z",
      "session": "20260328-160000-alice",
      "topic": "form_library",
      "plan_said": "Formik",
      "decided": "React Hook Form",
      "reason": "Formik incompatible with our validation pattern",
      "evidence": "src/components/TwoFactorSetup.tsx:12 — imports react-hook-form",
      "authority": "developer_approved",
      "tags": ["frontend", "forms"]
    }
  ],
  "rejected_approaches": [
    {
      "task_id": "T1",
      "timestamp": "2026-03-28T14:00:00Z",
      "session": "20260328-140000-bob",
      "approach": "Use qrcode npm package",
      "reason": "Generated blurry QR codes at high DPI",
      "evidence": "Test output: QR code resolution 150x150, expected 300x300",
      "tags": ["qr", "frontend", "image_quality"]
    }
  ],
  "open_questions": [
    {
      "task_id": "T5",
      "question": "Should we enforce 2FA immediately or grace period?",
      "raised_by": "20260328-180000-alice",
      "status": "unresolved"
    }
  ]
}
```

**Why `.story/` not `.acts/`**: Decisions are story-specific. They're made during story work, reference story tasks, and become irrelevant once the story is complete. The `.acts/` directory contains project-wide protocol definitions. Separating story data from protocol data keeps concerns clean.

### New field in `state.json`

```json
{
  "mcp_context": {
    "anchor_version": 3,
    "decisions_count": 5,
    "last_compaction": "2026-03-28T18:00:00Z",
    "loop_warnings": 0
  }
}
```

### Updated manifest (`acts.json`)

```json
{
  "mcp_context_engine": {
    "enabled": true,
    "server_path": ".acts/mcp-server",
    "transport": "stdio",
    "config": {
      "context_budget_default": 50000,
      "loop_threshold": 3,
      "turn_refresh_interval": 15,
      "compaction_auto_trigger": 10,
      "attention_optimization": true
    }
  }
}
```

---

## Directory Structure

```
.acts/
├── mcp-server/                    # Layer 7 implementation (future)
│   ├── package.json
│   ├── tsconfig.json
│   ├── README.md
│   └── src/
│       ├── index.ts               # McpServer + StdioServerTransport
│       ├── engine/
│       │   ├── context-engine.ts
│       │   ├── compaction.ts
│       │   ├── anchor.ts
│       │   ├── gap-detector.ts
│       │   └── learning-propagator.ts
│       ├── tools/
│       │   ├── begin-operation.ts
│       │   ├── get-context.ts
│       │   ├── record-decision.ts
│       │   ├── verify-state.ts
│       │   ├── update-anchor.ts
│       │   ├── compact-context.ts
│       │   ├── check-ownership.ts
│       │   └── propagate-learning.ts
│       ├── resources/
│       │   ├── story-state.ts
│       │   ├── story-board.ts
│       │   ├── ownership-map.ts
│       │   ├── task-context.ts
│       │   ├── task-anchor.ts
│       │   ├── task-learnings.ts
│       │   ├── session-current.ts
│       │   └── gaps.ts
│       ├── prompts/
│       │   ├── preflight.ts
│       │   ├── task-start.ts
│       │   ├── session-summary.ts
│       │   ├── handoff.ts
│       │   └── story-review.ts
│       └── lib/
│           ├── state-reader.ts
│           ├── session-reader.ts
│           ├── git-reader.ts
│           └── schema-validator.ts
├── schemas/
│   ├── state.json                 # existing + mcp_context field
│   ├── session-summary.json       # existing
│   ├── operation-meta.json        # existing
│   └── decisions.json             # NEW
├── operations/                    # existing
└── acts.json                      # existing + mcp_context_engine block
```

---

## How Each Problem Is Addressed

### #1 Instruction centrifugation

**Mechanism**: Context anchor is re-injected at the END of each context delivery (adjacent to where the agent generates its response). The `acts_update_anchor` tool produces a compact structured summary that the agent sees at maximum attention weight.

**Every `acts_task_start` prompt embeds the anchor as the last resource before the agent's work.** Constraints always attend with maximum weight.

### #2 Tool call residue

**Mechanism**: The MCP server replaces ad-hoc file reads with pre-formatted, compact context bundles. The context engine tracks what was delivered and skips redundant reads. No verbose tool call outputs accumulate.

### #3 Stale intermediate reasoning

**Mechanism**: `acts_record_decision` stamps decisions with timestamps and authority levels. When context is assembled, decisions override plan entries when they conflict. Authority hierarchy: `developer_approved` > `agent_decided` > plan entry.

### #4 Memory write corruption

**Mechanism**: `acts_verify_state` cross-references session summary claims against actual filesystem and git state. Checks `files_touched` vs `git diff`, `compiles` vs actual build, `tests_pass` vs actual test output.

### #5 Goal drift

**Mechanism**: The context anchor tracks an explicit goal/not-goal declaration. `acts_update_anchor` re-declares the goal every 15 turns. `acts_check_ownership` enforces scope boundaries by warning when agent modifies files outside its task.

### #6 Context drift

**Mechanism**: Operation-aware context delivery replaces static 9-step protocol. Server tracks budget, delivers incrementally, compacts automatically. Agent never accumulates file read outputs.

### #7 Lost in the middle

**Mechanism**: Context engine reorders content so critical items are at the END of each delivery. Inverts the Context Protocol's 1→9 order. Critical information always last (maximum attention). Historical context first (minimum attention).

### #8 Recursive loops

**Mechanism**: Server tracks tool call patterns. If `acts_get_context` is called with identical parameters 3+ times, server returns a loop warning with suggestion.

### #9 Handoff drift

**Mechanism**: `acts_propagate_learning` tags rejected approaches with semantic categories. When new developer starts (via `acts_begin_operation("handoff")`), server assembles learnings from ALL related tasks.

### #10 Hallucinated compliance

**Mechanism**: `acts_verify_state` requires specific evidence (file:line or quoted text). Server rejects vague claims. Runs actual commands to verify build/test/git status.

---

## Implementation Scope

This design spec covers the Layer 7 specification only. Implementation of the MCP server (TypeScript) is a follow-up task.

**Future implementation tasks**:
1. Create `.acts/schemas/decisions.json` schema ← **done in this spec**
2. Update `.acts/schemas/state.json` with `mcp_context` field
3. Update `.acts/acts.json` with `mcp_context_engine` block ← **done in this spec**
4. Create `.acts/mcp-server/` directory structure with README
5. Implement MCP server in TypeScript (`@modelcontextprotocol/sdk`)
6. Update `acts-v0.4.0.md` with §10 (Layer 7 spec)
7. Integration testing with Claude Code and Cursor
