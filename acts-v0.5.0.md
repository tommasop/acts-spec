# ACTS — Agent Collaborative Tracking Standard

**Version 0.5.0 — DRAFT**

A specification for multi-developer, multi-agent collaborative software development with structured handoffs, drift prevention, automated documentation, and mandatory code review gates.

---

## 1. Preamble

```text
Standard:    ACTS (Agent Collaborative Tracking Standard)
Version:     0.5.0
Status:      Draft
Authors:     Tommaso + contributors
Created:     2026-03-27
Updated:     2026-04-10
License:     CC-BY-SA-4.0
Supersedes:  0.4.0
```

### 1.1 Problem Statement

When multiple developers use AI coding agents on shared work, three failures emerge repeatedly:

1. **Drift** — agents diverge from the agreed technical design.
2. **Duplication** — agents reimplement already-completed work.
3. **Context loss** — handoffs between developers lose decisions, rationale, and state.

ACTS defines a minimal, tool-agnostic, versionable standard to eliminate these failures.

### 1.2 Design Principles

| Principle | Meaning |
|---|---|
| **Git-native** | All state lives in the repository. No external database required. |
| **Tool-agnostic** | Works with any AI coding agent, IDE, or CLI. |
| **Language-agnostic** | No assumptions about programming language or framework. |
| **Human-readable** | Every artifact is Markdown or JSON. A developer with no tooling can read the full state. |
| **Machine-readable** | Schemas are strict enough for agents to parse without ambiguity. |
| **Incremental** | Teams can adopt partially. Each layer adds value independently. |

### 1.3 Terminology

The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", "MAY" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

| Term | Definition |
|---|---|
| **Story** | A unit of work with a defined goal, acceptance criteria, and finite scope. Maps to a Jira story, GitHub issue, Linear ticket, etc. |
| **Task** | A subdivision of a story that can be assigned to one developer at a time. The atomic unit of work assignment. |
| **Session** | A continuous period of work by one developer (with or without an agent) on one task. |
| **Agent** | Any AI coding assistant (Claude Code, Cursor, Copilot, Codex, etc.) operating under developer supervision. |
| **Constitution** | The shared rules file (`AGENTS.md`) that all agents MUST follow. |
| **Tracker** | The `.story/` directory and its contents. |
| **Handoff** | The transfer of a task from one developer to another. |
| **Context Budget** | Maximum token allocation for an operation's context ingestion phase. |
| **Agent Compliance** | Self-reported record of which ACTS protocols an agent followed during a session. |
| **Report Protocol** | Standard formats for presenting information to humans during operations. |
| **Gate** | Explicit approval checkpoint in an operation where the agent MUST wait for human confirmation before proceeding. |
| **MCP Context Engine** | Layer 7 — an optional MCP server that provides operation-aware context delivery, compaction, anchoring, and verification. |
| **Context Anchor** | A compact structured summary of the current task state, re-injected at the end of context to maintain instruction attention. |
| **Decision Authority** | The trust level of a recorded decision: `developer_approved` (human-confirmed) or `agent_decided` (autonomous). |

### 1.4 Changes from v0.4.0

| Area | Change |
|------|--------|
| Git | Worktrees replaced by branch-per-task model — each task gets its own branch off the story branch |
| Git | Removed worktree concurrency model — branch isolation prevents conflicts |
| Gates | All gate types are now HARD STOPS — agent MUST NOT proceed without explicit human confirmation |
| Gates | Removed soft gate types: `GATE: acknowledge` and `GATE: reject` |
| Gates | New gate type: `GATE: task-review` — mandatory code review before task completion |
| Code Review | `task-review` promoted from optional to REQUIRED operation |
| Code Review | Tasks MUST have review approved before transitioning to DONE |
| Code Review | If `code_review.enabled=false`, task-review gate is skipped entirely |
| Validation | New validation: all DONE tasks must have review files or review was explicitly skipped |
| Validation | Branch-per-task validation replaces worktree validation |

---

## 2. Layers

ACTS is organized in seven layers. Each layer depends on the ones below it.

```text
┌─────────────────────────────────────────────┐
│  Layer 7: MCP CONTEXT ENGINE (OPTIONAL)     │
│  Operation-aware context delivery            │
│  Attention optimization, compaction          │
├─────────────────────────────────────────────┤
│  Layer 6: CODE REVIEW       (REQUIRED v0.4+)│
│  Generic interface + provider adapters      │
│  GitHuman (primary), CLI-based, extensible  │
├─────────────────────────────────────────────┤
│  Layer 5: ADAPTERS          (community)     │
│  Tool-specific bridges                      │
├─────────────────────────────────────────────┤
│  Layer 4: COMMUNICATION                     │
│  Changelog, tracker sync, newsletter        │
├─────────────────────────────────────────────┤
│  Layer 3: OPERATIONS                        │
│  Portable skill definitions (THE standard)  │
├─────────────────────────────────────────────┤
│  Layer 2: STATE                             │
│  Tracker directory, schemas, sessions       │
├─────────────────────────────────────────────┤
│  Layer 1: CONSTITUTION                      │
│  AGENTS.md — shared rules for all agents     │
└─────────────────────────────────────────────┘
```

**Layers 1–4** are the standard. **Layer 5** = community adapters, not governed by the spec. **Layer 6** is REQUIRED for ACTS v0.4.0+ conformance. **Layer 7** is OPTIONAL — it accelerates and improves existing layers but doesn't replace them.

A **minimal** ACTS implementation MUST include Layers 1 and 2. Layer 3 is REQUIRED for ACTS Standard conformance. Layer 4 is OPTIONAL. Layer 5 is community-maintained. Layer 6 is REQUIRED for code review features (v0.4.0+). Layer 7 is OPTIONAL for all conformance levels.

---

## 3. Layer 1: Constitution (`AGENTS.md`)

### 3.1 Location

The constitution MUST be a file named `AGENTS.md` at the repository root.

```text
<repo-root>/AGENTS.md
```

This aligns with the [AGENTS.md](https://agents.md/) industry standard, adopted by 60k+ open source projects and supported by Cursor, Claude Code, OpenCode, Copilot, Gemini CLI, and many other tools.

### 3.2 Format

AGENTS.md serves dual purpose:
1. **Project context** for any AI agent (setup, code style, testing)
2. **ACTS rules** for multi-developer coordination

A conforming AGENTS.md SHOULD include project context sections before ACTS sections:

| Section | Heading | Purpose |
|---|---|---|
| Setup | `## Setup` | How to install and run the project |
| Code Style | `## Code Style` | Formatting, naming conventions |
| Testing | `## Testing` | How to run tests |
| PR Instructions | `## PR Instructions` | Commit and PR conventions |

### 3.3 Required ACTS Sections

AGENTS.md MUST contain these ACTS sections, identified by their heading text exactly:

| Section | Heading | Purpose |
|---|---|---|
| Rules | `## Rules` | Absolute constraints all agents must obey |
| Architecture | `## Architecture` | Patterns, module structure, dependency direction |
| Style | `## Style` | Formatting, naming, file length conventions |
| Testing | `## Testing` | What must be tested and how |
| Git | `## Git` | Commit message format, branching model |
| Forbidden | `## Forbidden` | Patterns and practices that are never acceptable |

A conforming `AGENTS.md` MAY contain additional sections.

### 3.3 Rules Section — Required Directives

The `## Rules` section MUST contain at minimum these directives (phrasing may vary):

1. The agent MUST read the tracker state before writing code.
2. The agent MUST NOT modify files owned by a completed task without explicit developer approval.
3. The agent MUST record a session summary before ending work.
4. The agent MUST stay within the boundary of the assigned task.

### 3.4 Extension Mechanism

Teams MAY add a `## Extensions` section referencing additional files:

```markdown
## Extensions
- [Elixir conventions](./docs/agent/elixir.md)
- [Frontend conventions](./docs/agent/frontend.md)
```

Agents MUST read referenced extensions when working on files matching their scope.

---

## 4. Layer 2: State

### 4.1 Directory Structure

The tracker MUST live at `.story/` relative to the repository root (or worktree root).

```text
.story/
├── state.json              # REQUIRED — canonical story state
├── spec.md                 # REQUIRED — technical specification
├── plan.md                 # REQUIRED — execution plan with tasks
├── tasks/                  # RECOMMENDED — per-task notes
│   └── <task-id>/
│       └── notes.md
├── sessions/               # REQUIRED — session summaries
│   ├── <timestamp>-<developer>.md
│   └── compressed-<task-id>.md   # OPTIONAL — compressed briefings
├── jira-comments/          # OPTIONAL (Layer 4)
│   └── <timestamp>.md
└── newsletter.md           # OPTIONAL (Layer 4)
```

### 4.2 `state.json` Schema

The authoritative schema is shipped at `.acts/schemas/state.json`. Implementations MUST validate `state.json` against this schema.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://acts-standard.org/schemas/state/v0.3.0",
  "title": "ACTS Story State",
  "type": "object",
  "required": [
    "acts_version",
    "story_id",
    "title",
    "status",
    "spec_approved",
    "created_at",
    "updated_at",
    "context_budget",
    "tasks"
  ],
  "properties": {
    "acts_version": {
      "type": "string",
      "description": "ACTS specification version this file conforms to.",
      "pattern": "^\\d+\\.\\d+\\.\\d+$",
      "examples": ["0.3.0"]
    },
    "story_id": {
      "type": "string",
      "description": "External identifier (Jira key, GitHub issue number, etc.).",
      "examples": ["PROJ-42", "GH-123"]
    },
    "title": {
      "type": "string",
      "description": "Human-readable story title."
    },
    "status": {
      "type": "string",
      "enum": ["ANALYSIS", "APPROVED", "IN_PROGRESS", "REVIEW", "DONE"],
      "description": "Current story lifecycle status."
    },
    "spec_approved": {
      "type": "boolean",
      "description": "Whether the spec has been reviewed and approved."
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "updated_at": {
      "type": "string",
      "format": "date-time"
    },
    "context_budget": {
      "type": "integer",
      "minimum": 1000,
      "description": "Default context budget in tokens for operations on this story."
    },
    "tasks": {
      "type": "array",
      "items": { "$ref": "#/$defs/task" },
      "description": "Ordered list of tasks for this story."
    },
    "session_count": {
      "type": "integer",
      "minimum": 0,
      "description": "Count of session summary files."
    },
    "compressed": {
      "type": "boolean",
      "default": false,
      "description": "Whether compress-sessions has been run."
    },
    "metadata": {
      "type": "object",
      "description": "Extension point for team-specific data.",
      "additionalProperties": true
    },
    "mcp_context": {
      "type": "object",
      "description": "Layer 7 MCP Context Engine state. Only present when Layer 7 is enabled.",
      "properties": {
        "anchor_version": {
          "type": "integer",
          "minimum": 0,
          "description": "Version counter for the context anchor. Incremented each time acts_update_anchor is called."
        },
        "decisions_count": {
          "type": "integer",
          "minimum": 0,
          "description": "Total decisions recorded in .story/decisions.json."
        },
        "last_compaction": {
          "type": "string",
          "format": "date-time",
          "description": "ISO 8601 timestamp of the last compaction run."
        },
        "loop_warnings": {
          "type": "integer",
          "minimum": 0,
          "description": "Count of loop warnings emitted by the MCP server this story."
        }
      }
    },
    "jira_metadata": {
      "type": "object",
      "description": "Jira issue metadata. Present when the story was auto-fetched from Jira during story-init.",
      "properties": {
        "issue_key": {
          "type": "string",
          "description": "The Jira issue key (e.g. PROJ-305).",
          "examples": ["PROJ-305"]
        },
        "issue_type": {
          "type": "string",
          "description": "Jira issue type name (e.g. Story, Task, Bug).",
          "examples": ["Story", "Task", "Bug"]
        },
        "labels": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Labels assigned to the Jira issue."
        },
        "components": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Component names assigned to the Jira issue."
        },
        "url": {
          "type": "string",
          "format": "uri",
          "description": "Direct URL to the Jira issue."
        },
        "fetched_at": {
          "type": "string",
          "format": "date-time",
          "description": "ISO 8601 timestamp when the issue was fetched."
        }
      },
      "required": ["issue_key", "issue_type", "url", "fetched_at"]
    },
    "jira_task_map": {
      "type": "object",
      "description": "Mapping of ACTS task IDs to Jira subtask keys. Populated by plan-review when subtasks are created.",
      "additionalProperties": {
        "type": "string",
        "pattern": "^[A-Z]+-\\d+$",
        "description": "Jira subtask key (e.g. PROJ-306)."
      }
    }
  },
  "$defs": {
    "task": {
      "type": "object",
      "required": ["id", "title", "status", "assigned_to", "files_touched", "depends_on"],
      "properties": {
        "id": {
          "type": "string",
          "description": "Unique task identifier within the story.",
          "pattern": "^T\\d+$",
          "examples": ["T1", "T2"]
        },
        "title": {
          "type": "string"
        },
        "status": {
          "type": "string",
          "enum": ["TODO", "IN_PROGRESS", "BLOCKED", "DONE"]
        },
        "assigned_to": {
          "type": ["string", "null"],
          "description": "Developer handle or null if unassigned."
        },
        "files_touched": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Repository-relative paths of files created or modified."
        },
        "depends_on": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Task IDs that must be DONE before this task can start."
        },
        "context_priority": {
          "type": "integer",
          "minimum": 1,
          "maximum": 5,
          "default": 3,
          "description": "Context ingestion priority. 1=critical, 5=skim only."
        }
      }
    }
  }
}
```

### 4.3 Story Status — State Machine

```text
               approve
  ANALYSIS ──────────────► APPROVED
                              │
                              │ first preflight
                              ▼
                          IN_PROGRESS
                              │
                              │ all tasks DONE +
                              │ story-review pass
                              ▼
                            REVIEW
                              │
                              │ PR merged
                              ▼
                             DONE
```

Valid transitions:

| From | To | Trigger |
|---|---|---|
| `ANALYSIS` | `APPROVED` | Manual approval (`spec_approved` → `true`) |
| `APPROVED` | `IN_PROGRESS` | First preflight check |
| `IN_PROGRESS` | `REVIEW` | All tasks DONE + story-review passes |
| `REVIEW` | `DONE` | PR merged / external confirmation |
| `REVIEW` | `IN_PROGRESS` | Review reveals gaps → new tasks added |

### 4.4 Task Status — State Machine

```text
                preflight
  TODO ─────────────────────► IN_PROGRESS
                                  │
                    ┌─────────────┤
                    │             │
                    ▼             ▼
                 BLOCKED        DONE
                    │
                    │ unblocked
                    ▼
               IN_PROGRESS
```

| From | To | Trigger |
|---|---|---|
| `TODO` | `IN_PROGRESS` | Preflight check by assigned developer |
| `IN_PROGRESS` | `DONE` | Task completion within `task-start` |
| `IN_PROGRESS` | `BLOCKED` | Discovered dependency or external blocker |
| `BLOCKED` | `IN_PROGRESS` | Blocker resolved, new preflight |
| `IN_PROGRESS` | `TODO` | Developer fully abandons work (rare, requires rollback) |

### 4.5 `spec.md` Format

A conforming `spec.md` MUST contain these sections:

```markdown
# <STORY_ID> — <Title>

## Goal
<1-3 sentences: what this feature achieves from the user's perspective>

## Acceptance Criteria
<numbered list, each testable>

## Technical Decisions
<architecture choices, data model, APIs, libraries>

## Out of Scope
<explicitly listed exclusions>
```

Additional sections MAY be added.

### 4.6 `plan.md` Format

A conforming `plan.md` MUST contain a `## Tasks` section with one subsection per task:

```markdown
# Execution Plan — <STORY_ID>

## Tasks

### <TASK_ID> — <title>
- **Depends on:** <comma-separated task IDs or "none">
- **Files likely touched:** <list>
- **Context priority:** <1-5>
- **Acceptance:** <how to verify this task is complete>
```

The task IDs in `plan.md` MUST match the `id` fields in `state.json`.

### 4.7 Session Summary Format

Session files MUST be named `<YYYYMMdd-HHmmss>-<developer>.md` and placed in `.story/sessions/`.

A conforming session summary MUST contain these sections:

```markdown
# Session Summary
- **Developer:** <handle>
- **Date:** <ISO 8601 datetime>
- **Task:** <TASK_ID> — <title>

## What was done
<bullet list of concrete changes>

## Decisions made
<rationale for choices>

## What was NOT done (and why)
<remaining work, blocked items>

## Approaches tried and rejected
<what didn't work and why>

## Open questions
<unresolved items for next developer>

## Current state
- Compiles: ✅/❌
- Tests pass: ✅/❌
- Uncommitted work: ✅/❌

## Files touched this session
<list with brief description per file>

## Suggested next step
<what to do first when resuming>

## Agent Compliance
- Read AGENTS.md: ✅/❌
  - Sections confirmed: <list sections agent claims to have read>
- Read state.json: ✅/❌
- Followed preflight protocol: ✅/❌
- Followed context protocol: ✅/❌
  - Steps skipped: <list any, or "none">
- Deviated from plan: ✅/❌
  - Deviations: <list, or "none">
```

### 4.8 File Ownership

A file is **owned** by a task if it appears in that task's `files_touched` array.

Rules:

- A file MAY be owned by multiple tasks (e.g., `router.ex`).
- When a task is `DONE`, its owned files MUST NOT be modified by another task's agent **unless**:
  - The other task's `plan.md` entry explicitly names that file, **or**
  - The developer explicitly approves the modification.
- The preflight check MUST detect and warn about ownership conflicts.

---

## 5. Layer 3: Operations

### 5.1 Operation Definition Format

Every file in `.acts/operations/` MUST begin with a YAML frontmatter block followed by markdown prose.

The frontmatter schema is defined at `.acts/schemas/operation-meta.json`.

```yaml
---
operation_id: preflight
layer: 3
required: true
triggers: "APPROVED → IN_PROGRESS (first run only)"
context_budget: 50000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: developer
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/state.json exists and is valid"
  - "AGENTS.md exists at repo root"
postconditions:
  - "Task status is IN_PROGRESS"
  - "Task is assigned to developer"
  - "Agent has read and confirmed AGENTS.md"
  - "Agent has read all existing code from completed tasks"
---
```

The body MUST contain at minimum these sections:

| Section | Required | Purpose |
|---|---|---|
| Purpose | Yes | What this operation achieves |
| Inputs | Yes | Named inputs with types |
| Preconditions | Yes | What must be true before execution |
| Steps | Yes | Numbered execution steps |
| Report | If human approval needed | Information presented before gate |
| Gate | If state changes | Explicit approval checkpoint |
| Outputs | Yes | What is created/modified |
| Postconditions | Yes | What must be true after execution |
| Constraints | Yes | Hard rules during execution |
| Context Protocol | If layer 3, reads files | Priority-ordered context ingestion |

### 5.1.1 Report and Gate Sections

Operations that change state or require human oversight MUST include **Report** and **Gate** sections.

**Report Section** — Presents information to the human using standard formats from `.acts/report-protocol.md`:

- **Story Board** — Task status overview
- **Ownership Map** — Files owned by completed tasks
- **Scope Declaration** — What the agent will/won't do
- **Session State** — Build, test, lint, git status

**Gate Section** — Explicit checkpoint where the agent execution MUST stop completely.

All gates in ACTS are **HARD STOPS**. The agent MUST:

1. Present the gate prompt and any associated report
2. **STOP ALL EXECUTION** — do not take any further action
3. Wait for explicit human confirmation (a typed response)
4. Only proceed after receiving the expected confirmation

The agent MUST NOT:
- Auto-advance after a timeout
- Continue on silence or non-response
- Proceed based on assumed intent
- Skip gates for any reason (except when explicitly disabled in configuration)

```markdown
### Gate
GATE: approve
"Ready to proceed with <task_id>? (yes/no)"
Agent MUST stop here and wait. Do NOT update state.json until developer confirms.
```

**Gate types:**

- `GATE: approve` — Agent stops. Presents prompt. Waits for explicit "yes" to proceed. Any other response (including silence) means do not proceed.
- `GATE: task-review` — Agent stops. Triggers code review process. Task cannot complete until review status is `approved`. If code_review is disabled, this gate is SKIPPED entirely.

### 5.1.2 Gate Constraints

- The agent MUST NOT proceed past a gate without explicit human confirmation
- There are no timeouts on gates — the agent waits indefinitely
- If the human responds with anything other than the expected confirmation, the agent MUST ask again or abort
- Gates are not advisory — they are mandatory state transition requirements
- The only way to skip a gate is via explicit configuration (e.g., `code_review.enabled: false`)
- Violating gate constraints is a protocol violation and MUST be reported in the session summary Agent Compliance section

### 5.2 Context Protocol

Operations that read multiple files MUST include a `## Context Protocol` section.

The context budget is specified in the operation's frontmatter `context_budget` field (in tokens).

**Standard Context Protocol:**

```markdown
## Context Protocol

Budget: {context_budget} tokens

Priority order:
1. AGENTS.md — ALWAYS read in full
2. state.json — ALWAYS read in full
3. plan.md — ALWAYS read in full
4. Current task's plan.md entry — ALWAYS read in full
5. Current task's notes.md (if exists) — ALWAYS read in full
6. Completed dependency tasks' files_touched — read PUBLIC interfaces
   (exported functions, type signatures, module docs)
7. Session summaries for current task — read latest 3 in FULL,
   skim "Approaches tried and rejected" from older sessions
8. Session summaries for other tasks — read latest 1 only
9. Non-dependency completed task files — read module headers only

If budget is exhausted before step 9, STOP reading and note in
scope declaration what was NOT read.
```

Implementations MAY customize the protocol in their operation files, but MUST preserve steps 1–5 as always-read-in-full.

**Alternative: MCP Context Engine (Layer 7)**

When Layer 7 is enabled, the MCP server replaces the static 9-step protocol with operation-aware context delivery. The agent calls `acts_begin_operation` to receive a pre-assembled context bundle instead of reading files manually. This addresses 10 standard context failures including instruction centrifugation, tool call residue, stale reasoning, and context drift.

The MCP server delivers context in reverse priority order (critical items last) to exploit transformer recency bias. See §11 for the full Layer 7 specification.

### 5.3 Required Operations

A conforming ACTS Standard implementation MUST provide these operations:

| Operation | Triggers Transition | Context Budget |
|---|---|---|
| `story-init` | → `ANALYSIS` | 10,000 |
| `preflight` | `APPROVED` → `IN_PROGRESS` (first) | 50,000 |
| `session-summary` | none | 10,000 |
| `handoff` | none (reassignment) | 100,000 |
| `story-review` | `IN_PROGRESS` → `REVIEW` | 50,000 |

### 5.4 Optional Operations

| Operation | Purpose | Layer |
|---|---|---|
| `task-start` | Begin implementation with TDD loop | 3 |
| `compress-sessions` | Merge old session summaries | 3 |
| `plan-review` | Review task breakdown, optionally create Jira subtasks | 4 |
| `tracker-sync` | Sync ACTS task status to Jira subtasks | 4 |
| `changelog` | Generate/update CHANGELOG.md | 4 |
| `newsletter` | Generate company communication | 4 |

### 5.5 Operation: `story-init`

```markdown
---
operation_id: story-init
layer: 3
required: true
triggers: "(none) → ANALYSIS"
context_budget: 10000
required_inputs:
  - name: story_id
    type: string
    required: true
  - name: title
    type: string
    required: false
  - name: source
    type: string
    required: false
    description: "Raw requirements: pasted text, Jira description, PRD excerpt, or file path. If omitted and story_id matches a Jira key, auto-fetched from Jira."
optional_inputs: []
preconditions:
  - ".story/ directory MUST NOT already exist (or must be empty)"
  - "AGENTS.md MUST exist at repo root"
postconditions:
  - "state.json is valid per ACTS JSON Schema"
  - "All task IDs in plan.md match state.json"
  - "Status is ANALYSIS"
  - "No application code has been written"
---

# story-init

## Purpose

Initialize the ACTS tracker for a new story. Creates the `.story/`
directory, writes the technical specification from the provided
source material, decomposes it into an execution plan, and sets the
initial state.

## Steps

0. If `source` is omitted and `story_id` matches a Jira key
   pattern (`/^[A-Z]+-\d+$/`), auto-fetch the issue via the
   connected Atlassian MCP:
   - `description` (body) → used as `source`
   - `summary` → used as `title` (if not provided)
   - `issuetype`, `labels`, `components` → stored in `jira_metadata`
   If the fetch fails, prompt the user to provide source manually.

1. Create the tracker directory structure:
   ```

   .story/
   ├── state.json
   ├── spec.md
   ├── plan.md
   ├── tasks/
   └── sessions/

   ```

2. Parse the `source` material and write `.story/spec.md` with:
   - **Goal** — what the feature achieves (user perspective)
   - **Acceptance Criteria** — numbered, each independently testable
   - **Technical Decisions** — architecture choices, data model, APIs
   - **Out of Scope** — explicitly listed exclusions

3. Read `AGENTS.md` to understand architecture patterns and
   constraints. The plan MUST align with the constitution.

4. Decompose the spec into tasks. Write `.story/plan.md`:
   - Each task must be independently assignable to one developer
   - Identify dependency graph (which tasks block which)
   - Maximize parallelism — tasks that CAN run concurrently SHOULD
     NOT depend on each other
   - Each task gets: ID, title, dependencies, likely files,
     context priority (1-5), acceptance criteria

5. Initialize `.story/state.json`:
   - `acts_version`: `0.3.0`
   - `status`: `ANALYSIS`
   - `spec_approved`: `false`
   - `context_budget`: 50000 (default, adjustable)
   - `tasks`: one entry per task from the plan, all `TODO`
   - `session_count`: 0
   - `compressed`: false
   - `jira_metadata`: (only if auto-fetched from Jira in step 0)

6. Commit all tracker files:
   `docs(<story_id>): initialize ACTS tracker`

7. Instruct the developer to review `spec.md` and `plan.md` with
   the team before proceeding.

## Constraints

- Do NOT write any application code.
- Do NOT assume approval. The team must review first.
- Task IDs MUST follow the pattern `T<n>` (T1, T2, ...).
- The plan MUST reference architecture patterns from `AGENTS.md`.
- Context priority MUST be set for each task (1=critical, 5=skim).
```

### 5.6 Operation: `preflight`

```markdown
---
operation_id: preflight
layer: 3
required: true
triggers: "APPROVED → IN_PROGRESS (first run only)"
context_budget: 50000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: developer
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/state.json MUST exist and be valid"
  - "AGENTS.md MUST exist at repo root"
postconditions:
  - "Task status is IN_PROGRESS"
  - "Task is assigned to developer"
  - "Agent has read and confirmed AGENTS.md"
  - "Agent has read all existing code from completed tasks"
---

# preflight

## Purpose

Mandatory validation before any coding begins. Reads the full project
state, prevents drift and duplication, establishes the scope boundary,
and ingests context from prior work.

This is the single most important operation in ACTS. It is the
firewall between the agent and uncontrolled code generation.

## Steps

1. **READ CONSTITUTION**
   Read `AGENTS.md` in full. If it references extension files, read
   those too. Confirm to the developer that you have read it.

2. **READ STATE**
   Parse `.story/state.json`. Validate it against the ACTS schema
   at `.acts/schemas/state.json`.

3. **VALIDATE STORY STATUS**
   - `ANALYSIS` → REJECT. Say: "Spec not yet approved."
   - `REVIEW` or `DONE` → REJECT. Say: "Story is closed."
   - `APPROVED` → Transition to `IN_PROGRESS`.
   - `IN_PROGRESS` → Continue.

4. **VALIDATE TASK STATUS**
   - `DONE` → REJECT. List `files_touched`. Say: "Task already
     complete. If changes are needed, create a new task."
   - `IN_PROGRESS` assigned to a different developer → WARN. Display
     the latest session summary for this task. Ask the developer to
     confirm takeover (suggest using `handoff` instead).
   - `BLOCKED` → WARN. Show the blocker. Ask for confirmation.
   - `TODO` → Continue.

5. **VALIDATE DEPENDENCIES**
   For each task ID in `depends_on`:
   - If status is `DONE` → OK.
   - If status is NOT `DONE` → WARN. List unmet dependencies.
     Allow only if developer explicitly confirms.

6. **CONTEXT INGESTION**
   Follow the Context Protocol (§5.2). Report:
   a. Completed work summary
   b. Ownership map:
      ```
      File                        → Owned by
      lib/myapp/accounts.ex       → T1 (DONE)
      lib/myapp_web/router.ex     → T3 (IN_PROGRESS)
      ```
   c. Context report: which protocol steps were completed,
      which were skipped, estimated tokens used.

7. **CONCURRENCY CHECK**
   Check if this task is IN_PROGRESS by another developer:
   - If YES and both developers are in the SAME worktree → REJECT.
     Say: "Task locked by <developer>. Use a separate worktree
     or wait for their session-summary."
   - If YES and developers are in DIFFERENT worktrees → WARN.
     Show the other developer's latest session. Ask confirm.
   - If NO → continue.

8. **SCOPE DECLARATION**
   Read this task's entry from `.story/plan.md`. State:
   - What you WILL do (from the plan)
   - What you will NOT do (other tasks, out of scope)
   - Which existing files you may need to modify and why

9. **ASSIGN**
   Update `.story/state.json`:
   - Task status → `IN_PROGRESS`
   - `assigned_to` → `developer`
   - Story `updated_at` → now

10. **COMMIT**
    `chore(<story_id>): preflight T<n> by <developer>`

11. **CONFIRM**
    Say: "Pre-flight complete. Ready to implement <task_id>."

## Constraints

- This operation MUST NOT produce any application code.
- If any validation fails, STOP. Do not proceed to step 8+.
- The context ingestion (step 6) is not optional. Skipping it
  defeats the purpose of ACTS.
- The concurrency check (step 7) MUST reject same-worktree
  conflicts. This is not negotiable.
```

### 5.7 Operation: `task-start`

```markdown
---
operation_id: task-start
layer: 3
required: false
triggers: "none"
context_budget: 20000
required_inputs: []
optional_inputs: []
preconditions:
  - "preflight MUST have been run in this session for the target task"
  - "Task status MUST be IN_PROGRESS assigned to the current developer"
postconditions:
  - "Task acceptance criteria are met"
  - "All new public functions have documentation/types"
  - "Tests pass"
  - "Code follows AGENTS.md rules"
  - "files_touched accurately reflects all modified files"
---

# task-start

## Purpose

Execute the implementation of a task following the plan, the
constitution, and TDD principles.

## Steps

1. Re-read the task definition from `.story/plan.md`.

2. Implement following TDD (when the language/framework supports it):
   a. Write a failing test.
   b. Write the minimal code to make it pass.
   c. Refactor.
   d. Repeat.

3. After each meaningful unit of work, commit with a conventional
   commit message scoped to the story ID:
   `feat(<story_id>): <description>`

4. If you need to modify a file owned by a DONE task:
   a. Check the plan — does your task explicitly mention this file?
   b. If yes, proceed. Be surgical — change only what your task needs.
   c. If no, STOP. Ask the developer. If approved, note the deviation
      in `.story/tasks/<task_id>/notes.md`.

5. Maintain `.story/tasks/<task_id>/notes.md` throughout:
   - Decisions made and rationale
   - Deviations from the plan and why
   - Open questions

6. When the task is complete:
   a. Verify all acceptance criteria from `plan.md` for this task.
   b. Update `state.json`:
      - Task status → `DONE`
      - `files_touched` → complete list of files created or modified
   c. Commit: `feat(<story_id>): complete <task_id> — <summary>`

7. If you discover work that is needed but outside your task scope:
   a. Do NOT do it.
   b. Add a new task to `plan.md` and `state.json` with status `TODO`.
   c. Tell the developer.

## Constraints

- Stay within task boundary. No scope creep.
- Follow `AGENTS.md` patterns. If tempted to deviate, ask first.
- Every commit must compile and pass existing tests.
```

### 5.8 Operation: `session-summary`

```markdown
---
operation_id: session-summary
layer: 3
required: true
triggers: "none"
context_budget: 10000
required_inputs:
  - name: developer
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/state.json MUST exist"
  - "At least one task MUST be IN_PROGRESS or recently completed"
postconditions:
  - "Session file contains all required sections"
  - "Current state section reflects actual verified state"
  - "All work is committed and pushed"
---

# session-summary

## Purpose

Create a structured snapshot of the current session for handoff to
another developer or for your own future context. This is the primary
mechanism that prevents context loss.

## Steps

1. Generate filename: `<YYYYMMdd-HHmmss>-<developer>.md`

2. Create `.story/sessions/<filename>` with ALL sections defined in
   §4.7 (Session Summary Format), including the Agent Compliance
   section.

3. **VERIFY the "Current state" section** by actually checking:
   - Run the build/compile command
   - Run the test suite
   - Check `git status`
   Report EXACT output (pass/fail counts, not just ✅/❌).
   Do NOT guess or fabricate these.

4. **RECORD agent compliance** — fill the Agent Compliance section
   based on what was ACTUALLY done this session. Be honest about
   what was skipped.

5. Update `.story/state.json`:
   - `updated_at` → now
   - `session_count` → increment

6. Stage all changes and commit:
   `docs(<story_id>): session summary by <developer> for <task_id>`

7. Push the branch.

## Constraints

- Every section is REQUIRED. If a section has nothing to report,
  write "None" — do not omit the heading.
- Be thorough. This is the most-read artifact in ACTS.
- Never fabricate test results or build status.
- The Agent Compliance section must reflect reality. If you skipped
  the context protocol, say so. This enables the team to identify
  patterns of non-compliance.
```

### 5.9 Operation: `handoff`

```markdown
---
operation_id: handoff
layer: 3
required: true
triggers: "none (reassignment)"
context_budget: 100000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: developer
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/state.json MUST exist"
  - "Task SHOULD be IN_PROGRESS (by someone else) or TODO"
postconditions:
  - "New developer has full context from all prior sessions"
  - "Task is reassigned in state.json"
  - "No code has been written"
---

# handoff

## Purpose

Enable a new developer to take over a task with full context. Combines
preflight validation with deep context ingestion from all prior
sessions.

## Steps

1. **Run the full preflight sequence** (all steps from
   §5.6) with the given `task_id` and `developer`.

2. **Deep context ingestion:**
   a. Read ALL session summaries in `.story/sessions/` that reference
      this `task_id`, in chronological order. If a compressed session
      exists, read it FIRST, then read the latest uncompressed
      sessions.
   b. Read ALL session summaries for dependency tasks (to understand
      the foundation).
   c. Read ALL files in `files_touched` for this task (partial work).
   d. Read ALL files in `files_touched` for completed dependency tasks.

3. **Produce a handoff briefing** and display it:

   ```markdown
   ## Handoff Briefing: <task_id>

   ### Context
   <paragraph: what this task is about, where it fits in the story>

   ### Previous work
   <what was done, by whom, when — per session>

   ### Current code state
   <summary of what exists: files, functions, patterns used>

   ### Remaining work
   <specific items left to implement, derived from plan + sessions>

   ### Pitfalls to avoid
   <from "approaches tried and rejected" across all sessions>

   ### Open questions
   <aggregated from all sessions>

   ### Files to review
   <prioritized list: most important first, with reason>

   ### Context ingestion report
   - Sessions read: <count, list>
   - Compressed briefing used: yes/no
   - Files read: <count>
   - Estimated tokens used: <count>
   ```

1. Update `state.json`:
   - Task `assigned_to` → `developer`
   - `updated_at` → now

2. Commit:
   `chore(<story_id>): handoff <task_id> to <developer>`

3. **WAIT.** Ask the developer:
   "Ready to continue. Want me to start implementing, or do you have
   questions first?"

## Constraints

- MUST NOT begin coding until the developer explicitly confirms.
- The briefing MUST include the "Pitfalls to avoid" section even if
  empty — write "None reported" in that case.
- If there are zero prior sessions for this task (it's a fresh TODO),
  skip step 2a/2c and note "No prior work on this task" in the
  briefing.
- The context ingestion report enables the team to audit whether
  the agent actually read the context it claims to have read.

```

### 5.10 Operation: `story-review`

```markdown
---
operation_id: story-review
layer: 3
required: true
triggers: "IN_PROGRESS → REVIEW"
context_budget: 50000
required_inputs: []
optional_inputs: []
preconditions:
  - "ALL tasks in state.json MUST have status DONE"
  - "Story status MUST be IN_PROGRESS"
postconditions:
  - "Every acceptance criterion is verified against code"
  - "Tests pass"
  - "Constitution compliance verified"
  - "Story status is REVIEW"
---

# story-review

## Purpose

Final validation when all tasks are complete. Checks every acceptance
criterion against the implementation, runs the test suite, validates
constitution compliance, and prepares a PR description.

## Steps

1. **Verify all tasks DONE.**
   If any task is not `DONE`, list the incomplete tasks and STOP.

2. **Acceptance criteria check.**
   Read `.story/spec.md`. For each acceptance criterion:
   - Find the code and/or test that satisfies it.
   - Mark it ✅ with a reference (file + function/test name).
   - If a criterion is NOT met, mark it ❌ and STOP.
     Create a new task in plan.md and state.json for the gap.

3. **Run the full test suite.** Report exact results.

4. **Run formatter/linter.** Report results.

5. **Constitution compliance check:**
   - All public functions have documentation/types?
   - No forbidden patterns (per `AGENTS.md ## Forbidden`)?
   - Commit messages follow conventions (per `AGENTS.md ## Git`)?
   - File length limits respected?

6. **Agent compliance audit:**
   Read all session summaries. Check whether Agent Compliance
   sections indicate consistent protocol adherence. Report patterns:
   - "All sessions reported full compliance"
   - "3/7 sessions skipped context protocol step 6"
   - etc.

7. **Generate PR description:**

   ```markdown
   ## <story_id> — <title>

   ### Summary
   <what this story delivers, user perspective>

   ### Changes
   <per-task summary with key files>

   ### Testing
   <tests added/modified, how to verify manually>

   ### Notes for reviewers
   <key decisions, trade-offs, links to task notes>
   ```

1. **Update state:**
   - Story status → `REVIEW`
   - `updated_at` → now

2. Commit: `docs(<story_id>): story review complete`

3. **Trigger Layer 4 operations** (if configured):
    - Suggest running `changelog`
    - Suggest running `tracker-sync` with full summary
    - Suggest running `newsletter`

## Constraints

- If ANY criterion is unmet, do NOT transition to `REVIEW`.
- The PR description MUST be written for human reviewers, not agents.
- The agent compliance audit (step 6) is observational, not blocking.
  Non-compliance does not prevent REVIEW transition, but must be
  reported.

```

### 5.11 Operation: `compress-sessions`

```markdown
---
operation_id: compress-sessions
layer: 3
required: false
triggers: "none"
context_budget: 100000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: keep_latest
    type: integer
    required: false
    default: 3
optional_inputs: []
preconditions:
  - "At least 5 session summaries exist for the target task"
  - "The compressed file does NOT already exist (or developer confirms overwrite)"
postconditions:
  - "Compressed file contains merged decisions, approaches, and open questions"
  - "Original session files are preserved"
  - "state.json compressed flag is set"
---

# compress-sessions

## Purpose

Merge older session summaries for a task into a single compressed
briefing file, reducing context load for long-running stories while
preserving critical information (decisions, rejected approaches,
open questions).

## Steps

1. Read ALL session summaries for the task, in chronological order.

2. Keep the latest `keep_latest` sessions untouched.

3. For the remaining sessions, extract and merge:
   a. "Decisions made" — deduplicate, note date range
   b. "Approaches tried and rejected" — KEEP ALL, never compress
   c. "Open questions" — mark resolved ones, keep unresolved
   d. "Files touched this session" — union into one list
   e. "What was NOT done" — merge remaining items

4. Write `.story/sessions/compressed-<task_id>.md` with:
   - Header listing which sessions were merged (filenames + dates)
   - Clear statement: "This is a compressed summary, not original
     session data"
   - All merged content from step 3

5. The original session files are NOT deleted. They remain for
   audit purposes.

6. Update `state.json`:
   - `compressed` → `true`
   - `updated_at` → now

7. Commit: `chore(<story_id>): compress sessions for <task_id>`

## Constraints

- "Approaches tried and rejected" is NEVER compressed. Every
  reported approach must appear in the output.
- The compressed file MUST clearly state it is a compression,
  not original session data.
- This operation is RECOMMENDED when session_count exceeds 10
  for a single task.
```

### 5.12 Layer 4 Operations (Optional)

#### 5.12.1 Operation: `plan-review`

```markdown
---
operation_id: plan-review
layer: 4
required: false
triggers: "ANALYSIS → APPROVED"
context_budget: 15000
required_inputs:
  - name: story_id
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/ directory MUST exist with state.json, plan.md, spec.md"
  - "Story status MUST be ANALYSIS"
postconditions:
  - "spec_approved is true"
  - "Status is APPROVED"
  - "jira_task_map populated (if Jira subtasks created)"
---

# plan-review

## Purpose

Review the task breakdown generated by `story-init`. Present tasks
for explicit approval, allow modifications, and optionally create
Jira subtasks for each ACTS task under the parent story.

## Steps

1. Read `.story/state.json`, `.story/plan.md`, `.story/spec.md`.

2. Present a table of all tasks (ID, title, deps, priority,
   acceptance criteria) with the dependency graph.

3. **GATE: review** — Developer can approve, add, remove, or
   modify tasks. Loop until approved.

4. If `jira_integration.enabled` and `jira_metadata.issue_key`
   exists: offer to create Jira subtasks.

5. If subtask creation accepted: for each task, call Atlassian MCP
   to create a subtask (`issue_type: "Subtask"`, `parent: <key>`).
   Store returned keys in `state.json.jira_task_map`.

6. Set `spec_approved: true`, status → `APPROVED`.

7. Commit: `docs(<story_id>): plan review complete`.

## Constraints

- Do NOT write any application code.
- Jira subtask creation is optional.
- If `jira_task_map` already exists, only create subtasks for
  tasks missing from the map.
```

#### 5.12.2 Operation: `tracker-sync`

```markdown
---
operation_id: tracker-sync
layer: 4
required: false
triggers: "(none)"
context_budget: 10000
required_inputs:
  - name: story_id
    type: string
    required: true
  - name: task_id
    type: string
    required: false
    description: "Single task to sync. If omitted, syncs all tasks."
optional_inputs: []
preconditions:
  - ".story/ MUST exist with state.json"
  - "jira_task_map MUST exist in state.json"
postconditions:
  - "Jira subtask statuses match ACTS task statuses"
  - "ACTS state.json is unchanged"
---

# tracker-sync

## Purpose

Sync ACTS task status to Jira subtask status. ACTS is the source
of truth — this operation pushes state FROM ACTS TO Jira, never
the reverse.

## Status Mapping

| ACTS Status | Jira Transition |
|---|---|
| `TODO` | No change |
| `IN_PROGRESS` | → "In Progress" |
| `BLOCKED` | Add comment (no status change) |
| `DONE` | → "Done" |

## Steps

1. Read `.story/state.json`, validate `jira_task_map` exists.

2. Determine scope: single `task_id` or all tasks.

3. For each task: get available Jira transitions via Atlassian MCP,
   match ACTS status to a transition, apply it. Log result.

4. Bulk only: if all tasks `DONE` and story `REVIEW`, also
   transition parent issue.

5. Present sync report (task, ACTS status, Jira key, action, result).

## Constraints

- ACTS is ALWAYS the source of truth.
- If a transition fails, log and continue. Do not abort.
- Do NOT modify `state.json`. Only writes to Jira.
- Teams MAY customize the status mapping via
  `jira_integration.sync.status_map` in `.acts/acts.json`.
```

`changelog` and `newsletter` — unchanged from v0.2.0. See the v0.2.0 specification for full definitions.

---

## 6. Layer 4: Communication

### 6.1 Overview

Layer 4 handles bidirectional communication between ACTS and external
systems (issue trackers, documentation, notifications).

### 6.2 Operations

| Operation | Direction | Trigger | Description |
|---|---|---|---|
| `plan-review` | ACTS → Jira | ANALYSIS → APPROVED | Review task breakdown, optionally create Jira subtasks |
| `tracker-sync` | ACTS → Jira | Manual / suggestion | Push ACTS task status to Jira subtask status |
| `changelog` | ACTS → Git | story-review | Generate/update CHANGELOG.md |
| `newsletter` | ACTS → External | story-review | Generate company communication |

### 6.3 Jira Integration

When `jira_integration.enabled` is true in `.acts/acts.json`:

- **Inbound:** `story-init` auto-fetches issue description, summary,
  type, labels, and components from Jira when `story_id` matches the
  configured key pattern.
- **Outbound:** `plan-review` can create Jira subtasks under the
  parent issue. `tracker-sync` pushes ACTS task status to those
  subtasks on completion.
- **Mapping:** The `jira_task_map` in `state.json` stores the
  correspondence between ACTS task IDs (T1, T2, ...) and Jira
  subtask keys (PROJ-306, PROJ-307, ...).

ACTS is always the source of truth. Status sync is one-directional:
ACTS → Jira.

---

## 7. Git Integration

### 7.1 Branching Model

Each story uses a dedicated branch:

```text
story/<STORY_ID>       e.g., story/PROJ-42
```

Each task within a story uses a **dedicated sub-branch** off the story branch:

```text
story/<STORY_ID>/T1    e.g., story/PROJ-42/T1
story/<STORY_ID>/T2    e.g., story/PROJ-42/T2
```

**Branch lifecycle per task:**

1. **Branch created** — during preflight, before any coding begins
2. **Commits accumulate** — all work for the task happens on this branch
3. **Task completed** — branch is merged back into the story branch
4. **Branch deleted** — after successful merge

```text
story/PROJ-42 (story branch)
    ├── story/PROJ-42/T1 (task branch)
    │   ├── feat: add user model
    │   ├── feat: add validation
    │   └── ──MERGE──► (merged back to story/PROJ-42)
    └── story/PROJ-42/T2 (task branch)
        ├── feat: add API endpoint
        └── ──MERGE──► (merged back to story/PROJ-42)
```

### 7.2 Branch Isolation

ACTS v0.5.0 uses **branch-per-task** for isolation instead of git worktrees.

**Why not worktrees:**
- Worktrees have compatibility issues with some code review tools (e.g., GitHuman)
- Worktree setup is complex and error-prone
- Branch-per-task provides equivalent isolation with simpler tooling

**Isolation guarantees:**
- Each task operates on its own branch — no file conflicts between concurrent tasks
- The story branch (`story/<STORY_ID>`) is the integration point
- Task branches merge into the story branch sequentially after review
- No two task branches are merged simultaneously (enforced by preflight)

**For single-developer stories:**
- Task branches are RECOMMENDED but not REQUIRED
- Single-developer MAY work directly on the story branch

**Concurrent task coordination:**
- Two developers CAN work on different tasks simultaneously
- Each on their own task branch
- Merges to the story branch happen in dependency order
- If two tasks touch the same file, the later merge may need manual conflict resolution
- The preflight check warns about potential conflicts based on `files_touched`

### 7.3 Commits

All tracker state changes MUST be committed to the story branch. Commit messages for tracker changes MUST follow this format:

```text
<type>(<STORY_ID>): <description>
```

Where `type` is one of:

| Type | Usage |
|---|---|
| `docs` | Spec, plan, session summaries, changelog, newsletter |
| `chore` | State transitions, preflight, handoff, assignment changes |
| `feat` | Application code (task implementation) |
| `fix` | Bug fixes in application code |
| `test` | Test-only changes |
| `refactor` | Code restructuring without behavior change |

### 7.4 Tracker Atomicity

A state transition and its corresponding `state.json` update MUST be in the same commit as the merge of the task branch into the story branch. An implementation MUST NOT allow `state.json` to represent a state that doesn't match the repository contents.

**Task completion sequence:**
1. Task branch passes code review (task-review operation)
2. Merge task branch into story branch
3. Update `state.json` (task → DONE, files_touched)
4. Commit the merge and state change together

---

## 8. Validation & Conformance

### 8.1 Conformance Levels

| Level | Requires | Badge |
|---|---|---|
| **ACTS Basic** | Layer 1 + Layer 2 | `acts:basic` |
| **ACTS Standard** | Layer 1 + 2 + 3 | `acts:standard` |
| **ACTS Full** | Layer 1 + 2 + 3 + 4 | `acts:full` |

### 8.2 Validation Rules

An implementation MUST provide a `validate` command that checks:

```text
ACTS VALIDATION CHECKLIST v0.5.0
════════════════════════════════

Constitution:
  [ ] AGENTS.md exists at repo root
  [ ] Contains all required sections (Rules, Architecture, Style,
      Testing, Git, Forbidden)
  [ ] Rules section contains the 4 required directives

Schemas:
  [ ] .acts/schemas/state.json exists
  [ ] .acts/schemas/manifest.json exists
  [ ] .acts/schemas/operation-meta.json exists
  [ ] .acts/schemas/session-summary.json exists
  [ ] state.json validates against .acts/schemas/state.json
  [ ] acts.json validates against .acts/schemas/manifest.json

Report Protocol:
  [ ] .acts/report-protocol.md exists
  [ ] Defines Story Board format
  [ ] Defines Ownership Map format
  [ ] Defines Scope Declaration format
  [ ] Defines Session State format
  [ ] Defines Gate types (approve/task-review)

Operations:
  [ ] All required operations have valid frontmatter
  [ ] frontmatter operation_id matches filename
  [ ] frontmatter required_inputs have name + type + required
  [ ] All required operations have Context Protocol sections
      (preflight, handoff)
  [ ] Operations that change state have Report sections
  [ ] Operations that change state have Gate sections

Tracker:
  [ ] .story/ directory exists
  [ ] state.json validates against ACTS schema
  [ ] spec.md contains all required sections
  [ ] plan.md task IDs match state.json task IDs
  [ ] All session files match naming convention
  [ ] All session files contain required sections
  [ ] All session files contain Agent Compliance section

State consistency:
  [ ] Story status is valid per state machine
  [ ] All task statuses are valid per state machine
  [ ] No DONE task has empty files_touched
  [ ] No IN_PROGRESS task has null assigned_to
  [ ] Task dependency graph has no cycles
  [ ] updated_at >= created_at
  [ ] session_count matches actual file count
  [ ] context_budget is a positive integer (>= 1000)

Git consistency:
  [ ] All files in files_touched actually exist on disk
  [ ] All state.json changes are committed
  [ ] Branch name matches story/<STORY_ID> pattern
  [ ] Task branches exist for all IN_PROGRESS tasks
  [ ] Task branches are based on the current story branch head

Code Review (v0.5.0+):
  [ ] task-review operation exists and is marked required
  [ ] .story/reviews/active/ directory exists
  [ ] .story/reviews/archive/ directory exists
  [ ] ALL DONE tasks have review files in archive/ OR code_review was disabled
  [ ] review_status field exists on all DONE tasks in state.json
  [ ] No task transitions to DONE without passing task-review gate (when enabled)
```

### 8.3 Schema Versioning

The `acts_version` field in `state.json` declares which version of this specification the tracker conforms to.

- Patch version bumps (0.3.x) MAY fix typos and clarify language.
- Minor version bumps (0.x.0) MAY add new optional fields.
- Major version bumps (x.0) MAY change required fields or state machines.
- Implementations SHOULD validate that `acts_version` is a version they support.

---

## 9. Layer 6: Code Review Interface

### 9.1 Purpose

Layer 6 defines a generic CLI-based interface for code review tools, enabling mandatory human review of AI-generated code before task completion. This ensures code quality and maintains human oversight in AI-assisted development workflows.

### 9.2 Interface Specification

The interface is defined in `.acts/code-review-interface.json`:

```json
{
  "acts_version": "0.4.0",
  "interface_version": "1.0.0",
  "required_methods": ["check", "serve", "status", "export"],
  "required_outputs": ["review_status", "review_comments", "review_export"],
  "default_provider": "githuman",
  "providers": { ... }
}
```

### 9.3 Provider Configuration

Each provider MUST implement the CLI interface:

**Required Commands:**

- `check` — Verify provider is installed and available
- `serve` — Start review server for staged changes
- `status` — Get current review status
- `export` — Export review to file

**Example: GitHuman Provider**

Configuration in `.acts/review-providers/githuman.json`:

```json
{
  "provider": "githuman",
  "cli": "githuman",
  "min_version": "0.6.0",
  "commands": {
    "check": { "cmd": "githuman", "args": ["--version"] },
    "serve": { "cmd": "githuman", "args": ["serve", "--port", "3847"] },
    "export": { "cmd": "githuman", "args": ["export", "last"] }
  }
}
```

### 9.4 Review Lifecycle

**Active Reviews:**

- Location: `.story/reviews/active/`
- Accessible during task development
- Included in context ingestion (for current task only)

**Archived Reviews:**

- Location: `.story/reviews/archive/`
- Moved when task status → DONE
- Excluded from context ingestion
- Preserved for audit trail

### 9.5 Required Operations

**task-review** (REQUIRED for v0.4.0+)

- Implicitly run at task completion
- Gates task completion until review approved
- Exports review to `.story/reviews/active/`

**commit-review** (OPTIONAL)

- Explicit user request for mid-task review
- Informational only (does not gate completion)

### 9.6 Backward Compatibility

Projects without code review support:

- Set `code_review.enabled: false` in `.acts/acts.json`
- Continue using v0.3.0 workflow
- Can enable code review at any time

---

## 10. Extension Points

ACTS is designed to be extended without modifying the core standard.

### 9.1 Metadata Object

`state.json` includes an optional `metadata` object for team-specific data:

```json
{
  "metadata": {
    "jira_epic": "PROJ-10",
    "sprint": "2026-Q1-S6",
    "priority": "high",
    "estimated_points": 8
  }
}
```

Implementations MUST NOT require any specific key in `metadata`. Implementations MUST preserve unknown keys when updating `state.json`.

### 9.2 Custom Sections

`AGENTS.md`, `spec.md`, `plan.md`, and session summaries MAY include sections beyond those required by this specification. Implementations MUST NOT reject files with additional sections.

### 9.3 Custom Operations

Teams MAY define additional lifecycle operations beyond those in §5. Custom operations SHOULD:

- Be documented in a `## Custom Operations` section of `AGENTS.md`.
- Follow the operation definition format (§5.1) with valid frontmatter.
- Follow the same commit conventions (§7.3).
- Not violate state machine transitions (§4.3, §4.4).

### 9.4 Context Protocol Customization

Implementations MAY customize the Context Protocol steps for specific operations. However, steps 1–5 (AGENTS.md, state.json, plan.md, current task entry, current task notes) MUST always be read in full. Custom steps MAY be added between or after the standard steps.

---

## 11. Layer 7: MCP Context Engine

Layer 7 is OPTIONAL for all conformance levels. It provides operation-aware context delivery via an MCP (Model Context Protocol) server that sits between the filesystem and the AI agent.

### 11.1 Purpose

ACTS's Context Protocol (§5.2) defines a static 9-step reading order. Layer 7 replaces this with intelligent, operation-aware context delivery that addresses 10 well-documented failure modes in AI agent workflows:

| # | Problem | Failure Rate | MCP Solution |
|---|---------|-------------|--------------|
| 1 | Instruction centrifugation | 35.9% of failures | Anchor re-injected at context END |
| 2 | Tool call residue | Dominant after ~50 turns | Server-delivered bundles, no ad-hoc reads |
| 3 | Stale reasoning | 17% of failures | `decisions.json` overrides plan |
| 4 | Memory corruption | Compounds across sessions | `acts_verify_state` cross-checks claims |
| 5 | Goal drift | 35.9% of failures | Explicit goal/not-goal in anchor |
| 6 | Context drift | 35.6% of failures | Incremental delivery, auto-compaction |
| 7 | Lost in the middle | Universal | Critical items delivered last |
| 8 | Recursive loops | Burns tokens | Loop detection on repeated calls |
| 9 | Handoff drift | Multiplies across agents | Cross-task learning propagation |
| 10 | Hallucinated compliance | Self-reported today | Evidence-based verification |

See the design spec at `docs/superpowers/specs/2026-03-31-acts-layer7-mcp-context-engine-design.md` for full problem analysis with research citations.

### 11.2 Architecture

An MCP server at `.acts/mcp-server/` that reads/writes ACTS files. The file-based system remains the source of truth — the server is a context accelerator, not a replacement.

```
┌─────────────────────────────────────────────────────┐
│  AI Agent (Cursor, Claude Code, etc.)               │
├─────────────────────────────────────────────────────┤
│  ACTS MCP Server (.acts/mcp-server/)                │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │  Tools   │ │ Resources │ │     Prompts        │  │
│  └──────────┘ └───────────┘ └────────────────────┘  │
│  ┌──────────────────────────────────────────────┐   │
│  │         Context Engine (internal)            │   │
│  └──────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────┤
│  .story/ + .acts/ + AGENTS.md  (source of truth)    │
└─────────────────────────────────────────────────────┘
```

### 11.3 MCP Tools

A conforming Layer 7 implementation MUST expose these tools:

| Tool | Purpose | Problems Solved |
|------|---------|-----------------|
| `acts_begin_operation` | Start an operation, receive pre-assembled context bundle | #1, #5, #6, #7 |
| `acts_get_context` | Get next context chunk (incremental delivery) | #1, #2, #7 |
| `acts_record_decision` | Record decision with evidence and authority | #3, #4 |
| `acts_verify_state` | Cross-reference claims against actual state | #4, #10 |
| `acts_update_anchor` | Update context anchor (re-inject constraints) | #1, #5 |
| `acts_compact_context` | Compact sessions with preservation contract | #2, #3 |
| `acts_check_ownership` | Check file modification boundaries | #5, #6 |
| `acts_propagate_learning` | Share rejected approaches across tasks | #9 |

### 11.4 MCP Resources

A conforming Layer 7 implementation MUST expose these resources:

| Resource | URI | Content |
|----------|-----|---------|
| Story State | `acts://story/state` | Parsed, validated state.json |
| Story Board | `acts://story/board` | Computed task status table |
| Ownership Map | `acts://story/ownership` | Files owned by completed tasks |
| Task Context | `acts://task/{id}/context` | Full context bundle for operation |
| Task Anchor | `acts://task/{id}/anchor` | Compact structured summary (live) |
| Task Learnings | `acts://task/{id}/learnings` | Rejected approaches from ALL tasks |
| Session Current | `acts://session/current` | Live session state |
| Gaps | `acts://gaps` | Detected context gaps |

### 11.5 MCP Prompts

A conforming Layer 7 implementation MUST expose these prompts:

| Prompt | Parameters | Purpose |
|--------|-----------|---------|
| `acts_preflight` | `task_id`, `developer` | Preflight with context pre-loaded |
| `acts_task_start` | `task_id` | Implementation with scope/ownership/learnings |
| `acts_session_summary` | `developer` | Session recording with live verification |
| `acts_handoff` | `task_id`, `new_developer` | Handoff briefing with deep context |
| `acts_story_review` | — | Review with all ACs and compliance |

### 11.6 Attention Optimization

The context engine MUST deliver content in reverse priority order to exploit transformer recency bias:

```
[last]  ← Agent generates here (maximum attention)
  Anchor: goal, constraints, ownership
  Current task: plan entry + decisions override
  Dependency interfaces (if relevant)
  Rejected approaches from other tasks (if relevant)
  Session summaries (latest only, compacted)
  Historical context
[first] ← Minimum attention
```

### 11.7 Loop Detection

The server MUST track tool call patterns. If `acts_get_context` is called with identical parameters 3+ times consecutively, the server MUST return a loop warning.

### 11.8 `.story/decisions.json`

When Layer 7 is enabled, a `decisions.json` file MUST exist in `.story/`. It records structured decisions, rejected approaches, and open questions.

The authoritative schema is at `.acts/schemas/decisions.json`. The file contains three arrays:

- **`decisions`** — decisions that override or clarify plan entries. Each decision MUST include evidence (file:line or quoted text) and an authority level (`developer_approved` or `agent_decided`).
- **`rejected_approaches`** — approaches tried and found not to work. Preserved for cross-task learning. MUST never be compressed.
- **`open_questions`** — unresolved items needing developer input.

### 11.9 Configuration

Layer 7 is configured in `.acts/acts.json`:

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

### 11.10 Conformance

Layer 7 is OPTIONAL. An implementation MAY declare Layer 7 support without affecting its Basic, Standard, or Full conformance level. When Layer 7 is enabled, the MCP server MUST be compatible with the existing file-based operations — an agent that doesn't use the MCP server MUST still work correctly.

---

## 12. Reference Implementation

The reference implementation uses [Superpowers](https://github.com/obra/superpowers) skills and bash scripts. It is maintained at:

```text
https://github.com/<tbd>/acts-reference
```

The reference implementation provides ACTS Full conformance.

---

## Appendix A: Quick Reference Card

```text
┌──────────────────────────────────────────────────────┐
│                    ACTS v0.5.0 QUICK REF             │
│                                                      │
│  Files:                                              │
│    AGENTS.md             ← rules for all agents       │
│    .acts/acts.json      ← ACTS manifest              │
│    .acts/code-review-interface.json ← review API     │
│    .acts/report-protocol.md ← standard reports       │
│    .acts/operations/*   ← operation definitions      │
│    .acts/schemas/*      ← JSON schemas               │
│    .acts/review-providers/* ← provider configs       │
│    .acts/mcp-server/    ← Layer 7 MCP server         │
│    .story/state.json    ← canonical state            │
│    .story/spec.md       ← what to build              │
│    .story/plan.md       ← how to build it            │
│    .story/sessions/*    ← handoff artifacts          │
│    .story/reviews/*     ← code review artifacts      │
│    .story/decisions.json ← decisions + learnings     │
│                                                      │
│  Story:  ANALYSIS → APPROVED → IN_PROGRESS →         │
│          REVIEW → DONE                               │
│                                                      │
│  Task:   TODO → IN_PROGRESS → DONE                   │
│                    ↕                                  │
│                 BLOCKED                               │
│                                                      │
│  Before coding:     agent loads acts-preflight       │
│  Before stopping:   agent loads acts-session-summary │
│  Before takeover:   agent loads acts-handoff         │
│  Long sessions:     agent loads acts-compress-sessions│
│                                                      │
│  Human-in-the-loop: ALL gates are hard stops             │
│  Report protocol: standard formats for status        │
│  Context budget: operations declare token limits     │
│  Concurrency: branch-per-task for isolation             │
│  Compliance: session summaries record agent behavior │
│  Layer 7 (optional): MCP context engine              │
│                                                      │
│  Golden rule: the tracker is the source of truth.    │
└──────────────────────────────────────────────────────┘
```

## Appendix B: Shipped Schemas

The following JSON schemas are included in `.acts/schemas/`:

| File | Purpose |
|---|---|
| `state.json` | Validates `.story/state.json` |
| `manifest.json` | Validates `.acts/acts.json` |
| `session-summary.json` | Validates session summary structure |
| `operation-meta.json` | Validates operation frontmatter |
| `decisions.json` | Validates `.story/decisions.json` (Layer 7) |

## Appendix C: Report Protocol

The following report formats are defined in `.acts/report-protocol.md`:

| Report | Used In | Purpose |
|---|---|---|
| **Story Board** | preflight, handoff, story-review | Task status overview table |
| **Ownership Map** | preflight, handoff | Files owned by completed tasks |
| **Scope Declaration** | preflight, task-start | What agent will/won't do |
| **Session State** | session-summary | Build, test, lint, git status |
| **Code Review** | task-review, commit-review | Staged changes and review status |

**Gate Types:**

| Type | Behavior | Usage |
|---|---|---|
| `GATE: approve` | Wait for explicit "yes" | State changes, commits |
| `GATE: acknowledge` | Show report, any response continues | Informational displays |
| `GATE: reject` | Continue on silence, abort on "no" | Rare — destructive operations |
| `GATE: review` | External tool integration | Code review via GitHuman |

## Appendix D: Comparison with Existing Approaches

| Aspect | Raw git | Agile board only | ACTS v0.4.0 | ACTS v0.5.0 (Layer 7) |
|---|---|---|---|---|
| Agent-readable state | ❌ | ❌ | ✅ JSON schema | ✅ MCP resources |
| Drift prevention | ❌ | ❌ | ✅ Preflight check | ✅ Anchor + attention optimization |
| Handoff context | Commit msgs only | Ticket comments | ✅ Structured sessions + compression | ✅ Cross-task learning propagation |
| File ownership tracking | ❌ | ❌ | ✅ files_touched | ✅ acts_check_ownership |
| Versioned decisions | ❌ | ❌ | ✅ task notes + sessions | ✅ decisions.json with evidence |
| Human-in-the-loop | ❌ | ✅ (manual) | ✅ Gates with Report Protocol | ✅ Gates + loop detection |
| Code review | ❌ | Post-commit PR | ✅ Pre-commit mandatory | ✅ Pre-commit mandatory |
| AI code review | ❌ | ❌ | ✅ GitHuman integration | ✅ GitHuman integration |
| Works offline | ✅ | ❌ | ✅ git-native | ✅ git-native (MCP optional) |
| Tool-agnostic | ✅ | Varies | ✅ by design | ✅ by design |
| Context-aware | — | — | ✅ Context protocol | ✅ Operation-aware delivery |
| Observable | — | — | ✅ Agent compliance | ✅ Evidence-based verification |
| Concurrency-safe | — | — | ✅ Worktree model | ✅ Worktree model |
| Attention-optimized | — | — | ❌ | ✅ Reverse priority order |
| Loop detection | — | — | ❌ | ✅ MCP server tracking |
| Cross-task learning | — | — | ❌ | ✅ Rejected approach propagation |

---

This is a living document. To propose changes, open an issue or PR against the spec repository with the `acts-spec` label.
