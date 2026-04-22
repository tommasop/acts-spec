---
operation_id: story-init
layer: 3
required: true
triggers: "(none) → ANALYSIS"
context_budget: 10000
required_inputs:
  - name: story_id
    type: string
    required: false
    description: "Story identifier. If omitted and no source, triggers story-discover."
  - name: title
    type: string
    required: false
  - name: source
    type: string
    required: false
    description: "Raw requirements: pasted text, Jira description, PRD excerpt, or file path. If omitted and story_id matches a Jira key, auto-fetched from Jira."
optional_inputs:
  - name: from_draft
    type: boolean
    default: false
    description: "If true, use .story/draft-spec.md as source instead of creating new"
preconditions:
  - ".story/ directory MUST NOT already exist (or must be empty)"
  - "AGENTS.md MUST exist at repo root"
postconditions:
  - "state.json is valid per ACTS JSON Schema"
  - "All task IDs in plan.md match state.json"
  - "Status is ANALYSIS"
  - "No application code has been written"
  - "If from_draft: draft-spec.md promoted to spec.md"
---

# story-init

## Purpose

Initialize the ACTS tracker for a new story. Creates the `.story/`
directory, writes the technical specification from the provided
source material, decomposes it into an execution plan, and sets the
initial state.

## Steps

-1. **CHECK FOR DISCOVERY MODE**
    IF no story_id provided AND no source provided AND no from_draft:
    - Say: "No story_id or source material provided."
    - Run `story-discover` operation
    - Exit (discovery handles the rest)
    
    IF from_draft is true:
    - Check `.story/draft-spec.md` exists
    - If exists: use as source, skip to step 0
    - If not: STOP. Say: "No draft found at .story/draft-spec.md"

0. **FETCH FROM JIRA** (if `source` is omitted and `story_id` matches a Jira key pattern `/^[A-Z]+-\d+$/`)
   a. Call the Atlassian MCP tool to fetch the issue by key:
      - `description` (body) → used as `source`
      - `summary` → used as `title` (if not provided)
      - `issuetype` → stored in `jira_metadata`
      - `labels` → stored in `jira_metadata`
      - `components` → stored in `jira_metadata`
   b. Record `jira_metadata` object for state.json:
      ```
      jira_metadata:
        issue_key: "<story_id>"
        issue_type: "<from issuetype.name>"
        labels: [<from labels>]
        components: [<from components.name>]
        url: "<issue URL>"
        fetched_at: "<ISO 8601 timestamp>"
      ```
   c. If the fetch fails for any reason, prompt the user:
      "Could not fetch Jira issue <story_id>. Please provide the source material manually."
      Wait for input before continuing.
   d. If `story_id` does NOT match a Jira key pattern and `source` is omitted,
      prompt the user to provide source material manually.

1. **CREATE DIRECTORY STRUCTURE**
   ```
   .story/
   ├── state.json
   ├── spec.md
   ├── plan.md
   ├── tasks/
   └── sessions/
   ```

2. **SELECT STORY TEMPLATE** (if templates exist in `.acts/templates/`)
   Ask: "What type of story?"
   Options:
   - **feature**: New functionality (user-facing)
   - **bug**: Fix for existing issue
   - **refactor**: Code restructuring (no behavior change)
   - **spike**: Research/exploration
   - **config**: Setup, infrastructure, tooling
   
   If template chosen: load it, use as starting structure for spec.md
   If no template or no match: write spec from scratch (existing behavior)

3. **WRITE SPEC**
   IF from_draft:
   - Move `.story/draft-spec.md` → `.story/spec.md`
   - Update header: change "Draft — awaiting team review" to "Approved — team reviewed"
   - Update source line: "Draft specification (team reviewed)"
   - Remove "Open Questions" section if all answered
   - Save spec.md
   
   ELSE:
   - Parse the `source` material and write `.story/spec.md` with:
   - **Goal** — what the feature achieves (user perspective)
   - **Acceptance Criteria** — numbered, each independently testable
   - **Technical Decisions** — architecture choices, data model, APIs
   - **Out of Scope** — explicitly listed exclusions
   - **Acceptance Criteria** — numbered, each independently testable
   - **Technical Decisions** — architecture choices, data model, APIs
   - **Out of Scope** — explicitly listed exclusions

4. **READ CONSTITUTION**
   Read `AGENTS.md` to understand architecture patterns.
   The plan MUST align with the constitution.

5. **WRITE PLAN**
   Decompose the spec into tasks. Write `.story/plan.md`:
   - Each task independently assignable to one developer
   - Identify dependency graph
   - Maximize parallelism
   - Each task MUST include:
     - ID, title
     - **Description** — what the task does, implementation approach
     - **Acceptance Criteria** — numbered list of testable definitions of done
     - dependencies, likely files, context priority

6. **TASK APPROVAL LOOP**
   For each task in the plan, invoke the `task-approve` operation:
   
   ```bash
   echo '{
     "inputs": {
       "task_id": "T1",
       "title": "Task title",
       "description": "What this task does",
       "acceptance_criteria": ["criterion 1", "criterion 2"],
       "dependencies": ["T2"],
       "files_likely_touched": ["src/file.js"]
     }
   }' | acts run task-approve
   ```
   
   **GATE: task-approval**
   The task-approve operation will:
   - Display the task details
   - Ask developer to select:
     a. **Approve** — Task is acceptable as written
     b. **Modify** — Minor changes needed
     c. **Rewrite** — Major changes or complete redo
     d. **Your own answer** — Custom response
   
   Parse the output JSON:
   - If `approved: true` → proceed to next task
   - If `approved: false`:
     - Get explanation from `explanation` field
     - Update the task based on feedback
     - Re-invoke task-approve for the updated task
     - Loop until approved
   
   Continue until ALL tasks are approved.

7. **INIT STATE**
   Create `.story/state.json`:
   - `acts_version`: Read `manifest_version` from `.acts/acts.json`. Use that value.
   - `status`: `ANALYSIS`
   - `spec_approved`: `false`
   - `context_budget`: 50000 (default)
   - `tasks`: one entry per task, all `TODO`
   - Each task includes: `description`, `acceptance_criteria` (array)
   - `session_count`: 0
   - `compressed`: false
   - `jira_metadata`: (only if auto-fetched from Jira in step 0)

8. **PRESENT SUMMARY**
   Show:
   - Spec summary (goal, key acceptance criteria count)
   - Plan summary (number of tasks, dependency graph overview, all tasks approved)
   - State file initialized

9. **GATE: approve**
   Say: "Tracker initialized for <story_id>. All tasks reviewed and approved.
   Review the spec and plan with your team before proceeding. Ready to continue? (yes/no)"
   
   Wait for explicit "yes", then continue.

10. **COMMIT**
    `docs(<story_id>): initialize ACTS tracker`

11. **INSTRUCT**
    Say: "Team must review and approve `spec.md` and `plan.md` before
    proceeding. Set `spec_approved: true` in state.json when ready."

## Constraints

- Do NOT write any application code.
- Do NOT assume approval. The team must review first.
- Task IDs MUST follow pattern `T<n>`.
- The plan MUST reference architecture patterns from `AGENTS.md`.
- Each task MUST include a `description` explaining what it does.
- Each task MUST include `acceptance_criteria` — numbered list of testable criteria.
- Each task MUST be explicitly approved before initialization completes.
- If Modify, Rewrite, or Custom is selected, the developer MUST provide an explanation.
