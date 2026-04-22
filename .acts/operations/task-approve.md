---
operation_id: task-approve
layer: 3
required: true
triggers: "none"
context_budget: 10000
execution:
  type: "cli"
  command: "task-approve"
  timeout: 300
inputs_schema:
  task_id:
    type: string
    required: true
  title:
    type: string
    required: true
  description:
    type: string
    required: true
  acceptance_criteria:
    type: array
    items:
      type: string
    required: true
  dependencies:
    type: array
    items:
      type: string
    required: false
  files_likely_touched:
    type: array
    items:
      type: string
    required: false
outputs_schema:
  approved:
    type: boolean
  action:
    type: string
    enum: ["approve", "modify", "rewrite", "custom"]
  explanation:
    type: string
  task:
    type: object
---

# task-approve

## Purpose

Present a single task for explicit developer approval during story initialization. This is a HARD GATE - the agent MUST stop and wait for developer input.

## Steps

1. **DISPLAY TASK**
   Display the task details:
   ```
   Task <TASK_ID>: <title>
   
   Description: <what the task does>
   
   Acceptance Criteria:
   1. <criterion 1>
   2. <criterion 2>
   ...
   
   Dependencies: <list or "none">
   Files likely touched: <list>
   ```

2. **GATE: task-approval**
   Ask developer to select:
   a. **Approve** — Task is acceptable as written
   b. **Modify** — Minor changes needed
   c. **Rewrite** — Major changes or complete redo
   d. **Your own answer** — Custom response

3. **HANDLE RESPONSE**
   
   If **a. Approve** selected:
   - Output approved status
   - Exit with code 0
   
   If **b, c, or d** selected:
   - Ask: "Please explain what changes are needed:"
   - Wait for explanation
   - Output not-approved status with explanation
   - Exit with code 2

## Constraints

- This is a HARD GATE - agent MUST stop and wait for explicit approval
- If Approve is selected, task is approved
- If any other option is selected, caller must handle the explanation and re-call
- No timeouts - wait indefinitely for developer response
