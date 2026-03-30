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
   - `DONE` → REJECT. Present Story Board. Say: "Task already
     complete. If changes are needed, create a new task."
   - `IN_PROGRESS` assigned to a different developer → WARN. Display
     the latest session summary for this task. Say: "Task in progress
     by <developer>. Consider using 'handoff' instead. Confirm to proceed?"
   - `BLOCKED` → WARN. Show the blocker. Say: "Task is BLOCKED.
     Confirm you want to proceed anyway?"
   - `TODO` → Continue.

5. **VALIDATE DEPENDENCIES**
   For each task ID in `depends_on`:
   - If status is `DONE` → OK.
   - If status is NOT `DONE` → WARN. Present Story Board highlighting
     unmet dependencies. Say: "Dependencies not met: <list>.
     Confirm you want to proceed anyway?"

6. **CONTEXT INGESTION**
   Follow the Context Protocol (§5.2). Read files in priority order
   within the context_budget.

   Track which protocol steps you completed and which you skipped due
   to budget exhaustion.

7. **PRESENT REPORTS**
   Present **Story Board** per .acts/report-protocol.md
   Present **Ownership Map** showing files owned by DONE tasks
   Present **Scope Declaration** for this task per .acts/report-protocol.md
   Present context ingestion summary (steps completed, estimated tokens used)

8. **GATE: approve**
   Say: "Ready to proceed with <task_id>? (yes/no)"
   
   Do NOT proceed to step 9 until the developer explicitly confirms
   with "yes" or "proceed".
   
   If the developer says "no" or has concerns, address them and
   re-present the reports from step 7.

9. **CONCURRENCY CHECK**
   Check if this task is IN_PROGRESS by another developer:
   - If YES and both developers are in the SAME worktree → REJECT.
     Say: "Task locked by <developer>. Use a separate worktree
     or wait for their session-summary."
   - If YES and developers are in DIFFERENT worktrees → Already
     warned in step 4, continue.
   - If NO → continue.

10. **ASSIGN**
    Update `.story/state.json`:
    - Task status → `IN_PROGRESS`
    - `assigned_to` → `developer`
    - Story `updated_at` → now (ISO 8601)

11. **COMMIT**
    `chore(<story_id>): preflight T<n> by <developer>`

12. **CONFIRM**
    Say: "Pre-flight complete. Ready to implement <task_id>."

## Context Protocol

Budget: 50000 tokens

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

## Constraints

- This operation MUST NOT produce any application code.
- If any validation fails at step 3, STOP. Do not proceed.
- The context ingestion (step 6) is not optional.
- The concurrency check (step 9) MUST reject same-worktree conflicts.
- The gate (step 8) MUST be respected — no state changes without approval.
