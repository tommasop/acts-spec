# ACTS — Agent Collaborative Tracking Standard

**Version 0.3.0 — DRAFT**

A specification for multi-developer, multi-agent collaborative software development with structured handoffs, drift prevention, and automated documentation.

---

## 1. Preamble

```text
Standard:    ACTS (Agent Collaborative Tracking Standard)
Version:     0.3.0
Status:      Draft
Authors:     Tommaso + contributors
Created:     2026-03-27
Updated:     2026-03-27
License:     CC-BY-SA-4.0
Supersedes:  0.2.0
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
| **Constitution** | The shared rules file (`AGENT.md`) that all agents MUST follow. |
| **Tracker** | The `.story/` directory and its contents. |
| **Handoff** | The transfer of a task from one developer to another. |
| **Context Budget** | Maximum token allocation for an operation's context ingestion phase. |
| **Agent Compliance** | Self-reported record of which ACTS protocols an agent followed during a session. |
| **Report Protocol** | Standard formats for presenting information to humans during operations. |
| **Gate** | Explicit approval checkpoint in an operation where the agent MUST wait for human confirmation before proceeding. |

### 1.4 Changes from v0.2.0

| Area | Change |
|---|---|
| Architecture | Scripts removed — operations now agent-executed with human approval gates |
| Human-in-the-loop | Report Protocol added — standard formats for presenting information |
| Human-in-the-loop | Gates added to operations — explicit approval checkpoints |
| Schemas | JSON schemas now shipped in `.acts/schemas/`, not referenced by URL |
| Operations | YAML frontmatter added for machine-parseable metadata |
| Context | Context Protocol added — priority-ordered reading for token-limited agents |
| Concurrency | Worktree model is now normative for multi-developer stories |
| Sessions | Compression protocol for long-running stories |
| Observability | Agent Compliance section added to session summaries |
| Operations | New `compress-sessions` operation |
| Operations | New `validate` operation for interactive validation |

---

## 2. Layers

ACTS is organized in five layers. Each layer depends on the ones below it.

```text
┌─────────────────────────────────────────────┐
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
│  AGENT.md — shared rules for all agents     │
└─────────────────────────────────────────────┘
```

**Layers 1–4** are the standard. **Layer 5** = community adapters, not governed by the spec.

A **minimal** ACTS implementation MUST include Layers 1 and 2. Layer 3 is REQUIRED for ACTS Standard conformance. Layer 4 is OPTIONAL. Layer 5 is community-maintained.

---

## 3. Layer 1: Constitution (`AGENT.md`)

### 3.1 Location

The constitution MUST be a file named `AGENT.md` at the repository root.

```text
<repo-root>/AGENT.md
```

### 3.2 Required Sections

A conforming `AGENT.md` MUST contain these sections, identified by their heading text exactly:

| Section | Heading | Purpose |
|---|---|---|
| Rules | `## Rules` | Absolute constraints all agents must obey |
| Architecture | `## Architecture` | Patterns, module structure, dependency direction |
| Style | `## Style` | Formatting, naming, file length conventions |
| Testing | `## Testing` | What must be tested and how |
| Git | `## Git` | Commit message format, branching model |
| Forbidden | `## Forbidden` | Patterns and practices that are never acceptable |

A conforming `AGENT.md` MAY contain additional sections.

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
- Read AGENT.md: ✅/❌
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
  - "AGENT.md exists at repo root"
postconditions:
  - "Task status is IN_PROGRESS"
  - "Task is assigned to developer"
  - "Agent has read and confirmed AGENT.md"
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

**Gate Section** — Explicit checkpoint where the agent MUST wait for human confirmation:

```markdown
### Gate
GATE: approve
"Ready to proceed with <task_id>? (yes/no)"
Do NOT update state.json until developer confirms.
```

**Gate types:**
- `GATE: approve` — Wait for explicit "yes" (most common)
- `GATE: acknowledge` — Show report, any response continues
- `GATE: reject` — Continue on silence, abort on "no" (rare)

### 5.2 Context Protocol

Operations that read multiple files MUST include a `## Context Protocol` section.

The context budget is specified in the operation's frontmatter `context_budget` field (in tokens).

**Standard Context Protocol:**

```markdown
## Context Protocol

Budget: {context_budget} tokens

Priority order:
1. AGENT.md — ALWAYS read in full
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
| `tracker-sync` | Sync state to external issue tracker | 4 |
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
    required: true
  - name: source
    type: string
    required: true
    description: "Raw requirements: pasted text, Jira description, PRD excerpt, or file path"
optional_inputs: []
preconditions:
  - ".story/ directory MUST NOT already exist (or must be empty)"
  - "AGENT.md MUST exist at repo root"
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

3. Read `AGENT.md` to understand architecture patterns and
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

6. Commit all tracker files:
   `docs(<story_id>): initialize ACTS tracker`

7. Instruct the developer to review `spec.md` and `plan.md` with
   the team before proceeding.

## Constraints

- Do NOT write any application code.
- Do NOT assume approval. The team must review first.
- Task IDs MUST follow the pattern `T<n>` (T1, T2, ...).
- The plan MUST reference architecture patterns from `AGENT.md`.
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
  - "AGENT.md MUST exist at repo root"
postconditions:
  - "Task status is IN_PROGRESS"
  - "Task is assigned to developer"
  - "Agent has read and confirmed AGENT.md"
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
   Read `AGENT.md` in full. If it references extension files, read
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
  - "Code follows AGENT.md rules"
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
- Follow `AGENT.md` patterns. If tempted to deviate, ask first.
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

4. Update `state.json`:
   - Task `assigned_to` → `developer`
   - `updated_at` → now

5. Commit:
   `chore(<story_id>): handoff <task_id> to <developer>`

6. **WAIT.** Ask the developer:
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
   - No forbidden patterns (per `AGENT.md ## Forbidden`)?
   - Commit messages follow conventions (per `AGENT.md ## Git`)?
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

8. **Update state:**
   - Story status → `REVIEW`
   - `updated_at` → now

9. Commit: `docs(<story_id>): story review complete`

10. **Trigger Layer 4 operations** (if configured):
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

`tracker-sync`, `changelog`, `newsletter` — unchanged from v0.2.0. See the v0.2.0 specification for full definitions.

---

## 6. Layer 4: Communication

No changes from v0.2.0. Issue tracker sync, changelog generation, and newsletter generation remain optional Layer 4 features.

---

## 7. Git Integration

### 7.1 Branching Model

Each story MUST use a dedicated branch:

```text
story/<STORY_ID>       e.g., story/PROJ-42
```

### 7.2 Worktree Model

For multi-developer stories, each story MUST live in a dedicated git worktree:

```text
<repo-root>/
├── (main working directory)        # main branch
└── ../worktrees/
    └── <STORY_ID>/                 # story/<STORY_ID> branch
        ├── .story/
        ├── .acts/
        └── <application code>
```

This ensures:
- Only one developer modifies `state.json` per worktree
- Multiple developers can work on different tasks in parallel (each in their own worktree for the same story)
- No file-level locking needed

For single-developer stories, worktrees are RECOMMENDED but not REQUIRED.

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

A state transition and its corresponding `state.json` update MUST be in the same commit. An implementation MUST NOT allow `state.json` to represent a state that doesn't match the repository contents.

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
ACTS VALIDATION CHECKLIST v0.3.0
════════════════════════════════

Constitution:
  [ ] AGENT.md exists at repo root
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
  [ ] Defines Gate types (approve/acknowledge/reject)

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
  [ ] Worktree exists (for multi-developer stories)

Concurrency:
  [ ] No two IN_PROGRESS tasks assigned to different developers
      in the same worktree
```

### 8.3 Schema Versioning

The `acts_version` field in `state.json` declares which version of this specification the tracker conforms to.

- Patch version bumps (0.3.x) MAY fix typos and clarify language.
- Minor version bumps (0.x.0) MAY add new optional fields.
- Major version bumps (x.0) MAY change required fields or state machines.
- Implementations SHOULD validate that `acts_version` is a version they support.

---

## 9. Extension Points

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

`AGENT.md`, `spec.md`, `plan.md`, and session summaries MAY include sections beyond those required by this specification. Implementations MUST NOT reject files with additional sections.

### 9.3 Custom Operations

Teams MAY define additional lifecycle operations beyond those in §5. Custom operations SHOULD:

- Be documented in a `## Custom Operations` section of `AGENT.md`.
- Follow the operation definition format (§5.1) with valid frontmatter.
- Follow the same commit conventions (§7.3).
- Not violate state machine transitions (§4.3, §4.4).

### 9.4 Context Protocol Customization

Implementations MAY customize the Context Protocol steps for specific operations. However, steps 1–5 (AGENT.md, state.json, plan.md, current task entry, current task notes) MUST always be read in full. Custom steps MAY be added between or after the standard steps.

---

## 10. Reference Implementation

The reference implementation uses [Superpowers](https://github.com/obra/superpowers) skills and bash scripts. It is maintained at:

```text
https://github.com/<tbd>/acts-reference
```

The reference implementation provides ACTS Full conformance.

---

## Appendix A: Quick Reference Card

```text
┌──────────────────────────────────────────────────────┐
│                    ACTS v0.3.0 QUICK REF             │
│                                                      │
│  Files:                                              │
│    AGENT.md             ← rules for all agents       │
│    .acts/acts.json      ← ACTS manifest              │
│    .acts/report-protocol.md ← standard reports       │
│    .acts/operations/*   ← operation definitions      │
│    .acts/schemas/*      ← JSON schemas               │
│    .story/state.json    ← canonical state            │
│    .story/spec.md       ← what to build              │
│    .story/plan.md       ← how to build it            │
│    .story/sessions/*    ← handoff artifacts          │
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
│  Human-in-the-loop: gates require approval           │
│  Report protocol: standard formats for status        │
│  Context budget: operations declare token limits     │
│  Concurrency: worktrees required for multi-dev       │
│  Compliance: session summaries record agent behavior │
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

## Appendix C: Report Protocol

The following report formats are defined in `.acts/report-protocol.md`:

| Report | Used In | Purpose |
|---|---|---|
| **Story Board** | preflight, handoff, story-review | Task status overview table |
| **Ownership Map** | preflight, handoff | Files owned by completed tasks |
| **Scope Declaration** | preflight, task-start | What agent will/won't do |
| **Session State** | session-summary | Build, test, lint, git status |

**Gate Types:**

| Type | Behavior | Usage |
|---|---|---|
| `GATE: approve` | Wait for explicit "yes" | State changes, commits |
| `GATE: acknowledge` | Show report, any response continues | Informational displays |
| `GATE: reject` | Continue on silence, abort on "no" | Rare — destructive operations |

## Appendix D: Comparison with Existing Approaches

| Aspect | Raw git | Agile board only | ACTS v0.3.0 |
|---|---|---|---|
| Agent-readable state | ❌ | ❌ | ✅ JSON schema |
| Drift prevention | ❌ | ❌ | ✅ Preflight check |
| Handoff context | Commit msgs only | Ticket comments | ✅ Structured sessions + compression |
| File ownership tracking | ❌ | ❌ | ✅ files_touched |
| Versioned decisions | ❌ | ❌ | ✅ task notes + sessions |
| Human-in-the-loop | ❌ | ✅ (manual) | ✅ Gates with Report Protocol |
| Works offline | ✅ | ❌ | ✅ git-native |
| Tool-agnostic | ✅ | Varies | ✅ by design |
| Context-aware | — | — | ✅ Context protocol |
| Observable | — | — | ✅ Agent compliance |
| Concurrency-safe | — | — | ✅ Worktree model |

---

This is a living document. To propose changes, open an issue or PR against the spec repository with the `acts-spec` label.
