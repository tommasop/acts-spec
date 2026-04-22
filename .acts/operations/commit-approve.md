---
operation_id: commit-approve
layer: 3
required: true
triggers: "none"
context_budget: 15000
execution:
  type: "cli"
  command: "commit-approve"
  timeout: 300
inputs_schema:
  batch_number:
    type: integer
    required: true
  commit_count:
    type: integer
    required: true
  files_changed:
    type: array
    items:
      type: string
    required: true
  commit_messages:
    type: array
    items:
      type: string
    required: true
  test_results:
    type: string
    required: false
  lint_results:
    type: string
    required: false
outputs_schema:
  approved:
    type: boolean
  action:
    type: string
    enum: ["approved", "changes_requested"]
  feedback:
    type: string
---

# commit-approve

## Purpose

Review and approve a batch of commits during implementation. Called from task-start in strict mode.

## Steps

1. **DISPLAY BATCH REPORT**
   Show:
   - Batch number and commit count
   - List of files changed
   - Commit messages
   - Test results (if provided)
   - Lint results (if provided)

2. **GATE: commit-review**
   Ask developer to select:
   - **approved** — Continue with implementation
   - **changes_requested** — Address feedback first

3. **HANDLE RESPONSE**
   
   If **approved**:
   - Output approved status
   - Exit with code 0
   
   If **changes_requested**:
   - Ask for feedback/explanation
   - Output changes_requested status with feedback
   - Exit with code 2

## Constraints

- This is a HARD GATE — agent MUST stop and wait.
- No timeouts.
- This gate does NOT replace the task-review gate at task completion.
