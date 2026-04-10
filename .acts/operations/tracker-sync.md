---
operation_id: tracker-sync
layer: 4
required: false
triggers: "(none)"
context_budget: 10000
required_inputs:
  - name: story_id
    type: string
    required: true
  - name: task_id
    type: string
    required: false
    description: "Single task to sync. If omitted, syncs all tasks."
optional_inputs: []
preconditions:
  - ".story/ directory MUST exist with state.json"
  - "jira_task_map MUST exist in state.json"
postconditions:
  - "Jira subtask statuses match ACTS task statuses"
  - "ACTS state.json is unchanged (Jira is target, ACTS is source of truth)"
---

# tracker-sync

## Purpose

Sync ACTS task status to Jira subtask status. ACTS is the source
of truth — this operation pushes state FROM ACTS TO Jira, never
the reverse.

## Status Mapping

| ACTS Status | Jira Transition |
|---|---|
| `TODO` | No change (subtask stays in "To Do") |
| `IN_PROGRESS` | Transition to "In Progress" |
| `BLOCKED` | Add a comment with blocker reason (no status change) |
| `DONE` | Transition to "Done" |

## Steps

1. **READ STATE**
   Read `.story/state.json`.

2. **VALIDATE**
   a. Check `jira_task_map` exists. If not, say:
      "No Jira subtask mapping found. Run `plan-review` first
      to create subtasks." STOP.
   b. Check `jira_integration.enabled` is true in `.acts/acts.json`.
      If not, say: "Jira integration is disabled." STOP.

3. **DETERMINE SCOPE**
   If `task_id` is provided:
   - Validate it exists in `state.json.tasks`
   - Validate it exists in `jira_task_map`
   - Sync list: single task

   If `task_id` is omitted:
   - Sync list: all tasks in `jira_task_map`

4. **SYNC EACH TASK**
   For each task in the sync list:
   a. Read current ACTS status from `state.json`.
   b. Read `jira_task_map[task_id]` to get the Jira subtask key.
   c. Call Atlassian MCP to get available transitions:
      `atlassian_getTransitionsForJiraIssue` with the subtask key.
   d. Determine target transition based on status mapping above.
   e. If a matching transition exists, call
      `atlassian_transitionJiraIssue` to apply it.
   f. If ACTS status is `BLOCKED`, call
      `atlassian_addCommentToJiraIssue` with the blocker details
      from the task's notes.md (if available).
   g. Log result: synced / skipped / failed.

5. **SYNC STORY STATUS** (bulk only, when `task_id` is omitted)
   If all tasks are `DONE` and story status is `REVIEW`:
   a. Get parent issue key from `jira_metadata.issue_key`.
   b. Get available transitions for the parent issue.
   c. Transition the parent issue to match (e.g. "In Review").
   d. Log result.

6. **PRESENT SUMMARY**
   Present a sync report:

   | Task | ACTS Status | Jira Key | Jira Action | Result |
   |------|-------------|----------|-------------|--------|
   | T1   | DONE        | PROJ-306 | → Done      | synced |
   | T2   | IN_PROGRESS | PROJ-307 | → In Progress | synced |
   | T3   | TODO        | PROJ-308 | (none)      | skipped |

   Include counts: synced / skipped / failed.

7. **GATE: approve** (only if any failures)
   If any syncs failed, present failures and say:
   "Fix the issues above and re-run tracker-sync. Ready to continue? (yes/no)"

## Constraints

- ACTS is ALWAYS the source of truth. NEVER pull status from Jira
  into ACTS.
- If a Jira transition fails, log it and continue with remaining
  tasks. Do not abort.
- If `jira_task_map` is missing entries for some tasks, skip them
  silently (they were not created as subtasks).
- Do NOT modify `state.json`. This operation only writes to Jira.
- The status mapping table above is the default. Teams MAY customize
  via `jira_integration.sync.status_map` in `.acts/acts.json`.
