---
operation_id: task-review
layer: 3
required: true
triggers: "task completion (implicit)"
context_budget: 15000
execution:
  type: "cli"
  command: "task-review"
  timeout: 300
inputs_schema:
  task_id:
    type: string
    required: true
    validation: "^T\\d+$"
outputs_schema:
  review_status:
    type: string
    enum: ["approved", "changes_requested"]
  review_file:
    type: string
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
optional_inputs: []
preconditions:
  - "Task status MUST be IN_PROGRESS"
  - "All code changes are staged (git add completed)"
  - "Tests pass"
postconditions:
  - "Review status is recorded in state.json"
  - "If approved: task can transition to DONE"
  - "If changes_requested: task remains IN_PROGRESS"
  - "Review artifact is archived in .story/reviews/archive/"
---

# task-review

## Purpose

Mandatory code review before any task can be marked DONE. This operation
ensures human oversight of all AI-generated code. It is a HARD GATE —
the agent MUST NOT complete the task until review is approved.

**This operation is REQUIRED for ACTS v0.5.0 conformance.**

## Pre-check

If `code_review.enabled` is `false` in `.acts/acts.json`:
- Skip this entire operation
- Return immediately to task-start
- Log in session summary: "Code review gate skipped (disabled in config)"

## Steps

1. **STAGE ALL CHANGES**
   Run `git add .` to stage all pending changes.

2. **CHECK REVIEW PROVIDER**
   Check if review tool is configured and available:
   - IF tool configured (lazygit, etc.) AND available → proceed to step 3a
   - IF tool NOT available OR tool fails → proceed to step 3b

3a. **REVIEW VIA TOOL**
   a. Launch review tool
   b. Wait for developer to complete review in the tool
   c. Read review output
   d. IF approved → proceed to step 4
   e. IF changes_requested:
      - Present each comment
      - Address each concern
      - Re-stage: `git add .`
      - Loop back to step 2

3b. **MANUAL REVIEW FALLBACK**
   a. Show staged diff: `git diff --staged`
   b. Present files changed with line counts
   c. **GATE: approve** — Wait for developer to say "approved" or list changes requested
   d. IF approved → proceed to step 4
   e. IF changes listed:
      - Address each item
      - Re-stage: `git add .`
      - Loop back to step 2

4. **SAVE REVIEW ARTIFACT**
   Create `.story/reviews/active/<task_id>-review.md` with:
   ```markdown
   # Review — <task_id>
   - **Reviewer:** <developer or tool name>
   - **Date:** <ISO 8601>
   - **Status:** approved
   - **Files reviewed:** <list>
   - **Comments:** <any>
   ```

5. **ARCHIVE REVIEW**
   Move from `.story/reviews/active/` to `.story/reviews/archive/`

6. **UPDATE STATE**
   Set in `state.json`:
   - `review_status`: "approved"
   - `reviewed_at`: now (ISO 8601)
   - `reviewed_by`: developer name

7. **COMMIT**
   `docs(<story_id>): review approved for <task_id>`

## Constraints

- This is a HARD GATE — agent MUST stop and wait for approval.
- There are no timeouts. Agent waits indefinitely.
- If review provider fails, fall back to manual review — do NOT skip the gate.
- The review artifact MUST be saved before the task can transition to DONE.
- If code_review is disabled, this entire operation is skipped.
