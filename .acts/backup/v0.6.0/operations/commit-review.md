---
operation_id: commit-review
layer: 3
required: true
required_for: "strict"
triggers: "after a batch of commits during implementation"
context_budget: 10000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: batch_commits
    type: array
    required: true
    description: "List of commit SHAs in this batch"
optional_inputs: []
preconditions:
  - "Task status MUST be IN_PROGRESS"
  - "At least one commit has been made since last review"
postconditions:
  - "Batch is approved or changes are requested"
  - "If approved: agent continues implementation"
  - "If changes_requested: agent addresses feedback and re-presents"
---

# commit-review

## Purpose

In strict mode, review a batch of commits before continuing implementation.
The agent groups logical changes into batches and requests human review
after each batch. This prevents accumulating unreviewed work.

**This operation is REQUIRED for ACTS Strict conformance.**

## Pre-check

If conformance level is NOT `strict` in `.acts/acts.json`:
- Skip this entire operation
- Continue implementation freely

## Steps

1. **DETERMINE BATCH BOUNDARIES**
   A batch is 1-5 commits. Batch when ANY of these is true:
   - You've completed a logical unit (e.g., "model layer done", "API endpoint done")
   - You've made 5 commits since last review
   - Tests now pass for a major component
   - You're about to start a different component or pattern
   
   Do NOT batch when:
   - Tests are failing (fix them first)
   - You have uncommitted changes that don't compile
   - The batch would be a pure refactor (review separately)
   
   Check `.acts/acts.json` for `batch_size_hint` if configured:
   - {"min": N, "max": M} — respect these bounds

2. **COMPILE BATCH REPORT**
   Gather:
   - Commit SHAs and one-line messages
   - Files changed with line stats
   - Test results
   - Lint results

3. **PRESENT COMMIT BATCH REPORT**
   Present per .acts/report-protocol.md

4. **GATE: commit-review**
   Say: "Batch complete: <N> commits, <M> files changed. Ready to review?"

   Agent MUST stop here and wait for explicit "approved" or "changes_requested".

5. **HANDLE RESPONSE**
   If "approved":
   - Continue implementation
   - Next batch starts with next commit

   If "changes_requested":
   - Read specific feedback
   - Address each concern
   - Re-commit if needed
   - LOOP back to step 2

## Constraints

- This is a HARD GATE — agent MUST stop and wait.
- There are no timeouts.
- The agent decides batch size — human can ask for smaller/larger batches.
- This gate does NOT replace the task-review gate at task completion.
- Both gates are required in strict mode.
