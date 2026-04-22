---
operation_id: plan-approve
layer: 3
required: true
triggers: "ANALYSIS → APPROVED"
context_budget: 15000
execution:
  type: "cli"
  command: "plan-approve"
  timeout: 300
inputs_schema:
  story_id:
    type: string
    required: true
  tasks:
    type: array
    items:
      type: object
      properties:
        id: { type: string }
        title: { type: string }
        dependencies: { type: array }
        priority: { type: integer }
    required: true
  dependency_graph:
    type: string
    required: false
outputs_schema:
  approved:
    type: boolean
  action:
    type: string
    enum: ["approve", "add", "remove", "modify"]
  modifications:
    type: array
    required: false
---

# plan-approve

## Purpose

Review and approve the task breakdown plan during story initialization.

## Steps

1. **DISPLAY TASK TABLE**
   Present all tasks with:
   - ID, title, dependencies, priority
   - Dependency graph visualization

2. **GATE: approve**
   Ask developer to select:
   - **approve** — accept as-is
   - **add** — add a new task
   - **remove** — remove a task
   - **modify** — change task details

3. **HANDLE RESPONSE**
   
   If **approve**:
   - Output approved status
   - Exit with code 0
   
   If **add/remove/modify**:
   - Output changes_requested with action details
   - Exit with code 2

## Constraints

- This is a HARD GATE — agent MUST stop and wait.
- Loop until approve is selected.
- All tasks must be approved before story can proceed.
