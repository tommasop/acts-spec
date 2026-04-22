---
operation_id: story-approve
layer: 3
required: true
triggers: "IN_PROGRESS → REVIEW"
context_budget: 20000
execution:
  type: "cli"
  command: "story-approve"
  timeout: 300
inputs_schema:
  story_id:
    type: string
    required: true
  title:
    type: string
    required: true
  acceptance_criteria_met:
    type: integer
    required: true
  acceptance_criteria_total:
    type: integer
    required: true
  tests_passing:
    type: integer
    required: true
  tests_total:
    type: integer
    required: true
  all_tasks_reviewed:
    type: boolean
    required: true
  compliance_issues:
    type: array
    required: false
outputs_schema:
  approved:
    type: boolean
  story_status:
    type: string
    enum: ["REVIEW", "IN_PROGRESS"]
---

# story-approve

## Purpose

Final approval gate before transitioning story from IN_PROGRESS to REVIEW.

## Steps

1. **DISPLAY STORY REPORT**
   Show:
   - Story ID and title
   - Acceptance criteria met/total
   - Tests passing/total
   - All tasks reviewed: yes/no
   - Any compliance issues
   - PR description summary

2. **GATE: approve**
   Say: "Story review complete. Ready to transition to REVIEW? (yes/no)"
   
   If ANY criterion is unmet, do NOT offer this gate.

3. **HANDLE RESPONSE**
   
   If **yes**:
   - Output approved status with story_status: REVIEW
   - Exit with code 0
   
   If **no**:
   - Output not approved with story_status: IN_PROGRESS
   - Exit with code 2

## Constraints

- This is a HARD GATE — agent MUST stop and wait.
- Do NOT offer gate if criteria are unmet.
- No timeouts.
