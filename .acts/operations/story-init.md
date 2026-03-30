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

1. **CREATE DIRECTORY STRUCTURE**
   ```
   .story/
   ├── state.json
   ├── spec.md
   ├── plan.md
   ├── tasks/
   └── sessions/
   ```

2. **WRITE SPEC**
   Parse the `source` material and write `.story/spec.md` with:
   - **Goal** — what the feature achieves (user perspective)
   - **Acceptance Criteria** — numbered, each independently testable
   - **Technical Decisions** — architecture choices, data model, APIs
   - **Out of Scope** — explicitly listed exclusions

3. **READ CONSTITUTION**
   Read `AGENTS.md` to understand architecture patterns.
   The plan MUST align with the constitution.

4. **WRITE PLAN**
   Decompose the spec into tasks. Write `.story/plan.md`:
   - Each task independently assignable to one developer
   - Identify dependency graph
   - Maximize parallelism
   - Each task: ID, title, dependencies, likely files, acceptance

5. **INIT STATE**
   Create `.story/state.json`:
   - `acts_version`: `0.3.0`
   - `status`: `ANALYSIS`
   - `spec_approved`: `false`
   - `context_budget`: 50000 (default)
   - `tasks`: one entry per task, all `TODO`
   - `session_count`: 0
   - `compressed`: false

6. **PRESENT SUMMARY**
   Show:
   - Spec summary (goal, key acceptance criteria count)
   - Plan summary (number of tasks, dependency graph overview)
   - State file initialized

7. **GATE: acknowledge**
   Say: "Tracker initialized for <story_id>. Review the spec and plan
   with your team before proceeding. Continue when ready."
   
   Wait for any response, then continue.

8. **COMMIT**
   `docs(<story_id>): initialize ACTS tracker`

9. **INSTRUCT**
   Say: "Team must review and approve `spec.md` and `plan.md` before
   proceeding. Set `spec_approved: true` in state.json when ready."

## Constraints

- Do NOT write any application code.
- Do NOT assume approval. The team must review first.
- Task IDs MUST follow pattern `T<n>`.
- The plan MUST reference architecture patterns from `AGENTS.md`.
