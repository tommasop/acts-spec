---
operation_id: task-review
layer: 3
required: true
triggers: "task completion (implicit)"
context_budget: 15000
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
   If a review provider is configured (e.g., lazygit):
   a. Run `check` command to verify provider is available
   b. If provider is available → proceed to step 3a
   c. If provider is NOT available → proceed to step 3b

3a. **REVIEW VIA TOOL**
   a. Run `review` command to launch the TUI review interface
      (e.g., `lazygit` — opens TUI for interactive review,
      human reviews diffs and tells agent the result)
   b. Present Code Review report (from .acts/report-protocol.md)
   c. **GATE: task-review** — Agent MUST stop and wait for review output
   d. Capture the structured Markdown output from the tool
   e. Parse review comments from the output
   f. If status is `approved` → proceed to step 4
   g. If status is `changes_requested`:
      - Read review comments
      - Address each comment
      - Re-stage changes
      - Loop back to step 3a

3b. **MANUAL REVIEW FALLBACK**
   a. Show full diff of staged changes
   b. Present Code Review report
   c. **GATE: approve** — Agent MUST stop and wait for explicit "yes"
   d. If developer approves → proceed to step 4
   e. If developer requests changes:
      - Address feedback
      - Re-stage changes
      - Loop back to step 3b

4. **EXPORT REVIEW**
   If a review tool was used:
   - Run `export` command
   - Save to `.story/reviews/active/<task_id>-review.md`
   
   If manual review:
   - Create `.story/reviews/active/<task_id>-review.md` with:
     ```markdown
     # Manual Review — <task_id>
     - **Reviewer:** <developer>
     - **Date:** <ISO 8601>
     - **Status:** approved
     - **Changes reviewed:** <list of files>
     ```

5. **ARCHIVE REVIEW**
   Move review from `.story/reviews/active/` to `.story/reviews/archive/`

6. **UPDATE STATE**
   Set `review_status` for this task in `state.json`:
   ```json
   {
     "id": "T1",
     "review_status": "approved",
     "reviewed_at": "2026-04-10T14:30:00Z",
     "reviewed_by": "developer"
   }
   ```

7. **COMMIT**
   `docs(<story_id>): review approved for <task_id>`

## Constraints

- This is a HARD GATE — agent MUST stop and wait for approval.
- There are no timeouts. Agent waits indefinitely.
- If review provider fails, fall back to manual review — do NOT skip the gate.
- The review artifact MUST be saved before the task can transition to DONE.
- If code_review is disabled, this entire operation is skipped.
