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
  story_id:
    type: string
    required: false
outputs_schema:
  review_status:
    type: string
    enum: ["approved", "changes_requested", "cancelled"]
  review_file:
    type: string
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
optional_inputs:
  - name: story_id
    type: string
    required: false
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

**This operation is REQUIRED for ACTS v0.5.0+ conformance.**

## Pre-check

If `code_review.enabled` is `false` in `.acts/acts.json`:
- Skip this entire operation
- Return immediately to task-start
- Log in session summary: "Code review gate skipped (disabled in config)"

## Review Providers

The task-review operation supports multiple review providers with automatic fallback:

1. **GitHuman** (default) - Web-based code review interface
2. **lazygit** - Terminal UI (TUI) for git operations  
3. **Manual** - Command-line diff review with interactive prompts

Provider selection: `ACTS_REVIEW_PROVIDER=githuman|lazygit|manual|auto`

## GitHuman Review Flow (Default)

GitHuman provides a web-based interface for reviewing staged changes:

### Step 1: Launch GitHuman Server
- Start `githuman serve --port 3847 --no-open`
- Wait for server health check
- Server runs at `http://127.0.0.1:3847`

### Step 2: Present Review Menu
The agent displays:
```
═══════════════════════════════════════════════════════════════════
🌐 GITHUMAN CODE REVIEW READY
═══════════════════════════════════════════════════════════════════

GitHuman is now running and ready for your review:

  📍 URL: http://127.0.0.1:3847
  🔧 Server PID: <pid>

📋 INSTRUCTIONS:

  1. Open your browser to: http://127.0.0.1:3847
  2. Review the staged changes in GitHuman
  3. Close/submit your review in the GitHuman interface
  4. Return here and select an option from the menu below

🔍 REVIEW MENU - Select an option:

  [1] ✅ Approved - Changes look good, ready to merge
  [2] 📝 Changes Requested - Need modifications before approval
  [3] ❌ Cancel - Abort review, keep task in progress

Enter your choice (1/2/3): 
```

### Step 3: Developer Reviews in Browser
- Open browser to `http://127.0.0.1:3847`
- Review staged changes
- Submit review in GitHuman interface

### Step 4: Developer Selects Menu Option
- **Option 1 (Approved)**: Proceed to export and complete
- **Option 2 (Changes Requested)**: Enter comments, task stays IN_PROGRESS
- **Option 3 (Cancel)**: Abort review, task stays IN_PROGRESS

### Step 5: Export Review
- Run `githuman export last --output <file>`
- Saves to `.story/reviews/active/<task_id>-githuman-export.md`

### Step 6: Stop GitHuman Server
- Kill server process
- Verify server stopped

### Step 7: Create Review Artifact
- Generate `.story/reviews/active/<task_id>-review.md`
- Archive to `.story/reviews/archive/`

### Step 8: Handle Result
- **Approved**: Return success, task can transition to DONE
- **Changes Requested**: Return changes_requested, developer must:
  1. Make requested changes
  2. Stage: `git add .`
  3. Re-run: `acts run task-review --input task_id=<task_id>`

## lazygit Review Flow

For terminal-based review:

1. Launch `lazygit` focused on staged changes
2. Present menu after lazygit exits:
   - `[1] Approved`
   - `[2] Changes Requested`  
   - `[3] Cancel`
3. Create review artifact based on selection
4. Archive and return status

## Manual Review Flow

When no tools are available:

1. Display formatted diff summary (summary or full mode)
2. Show review checkpoints (security, tests, docs, etc.)
3. Present interactive menu:
   - `[1] Approved`
   - `[2] Changes Requested`
   - `[3] Cancel`
4. Wait for developer input (reads from `/dev/tty` or file-based fallback)
5. Create and archive review artifact

**Manual Review Modes:**
- `ACTS_REVIEW_MODE=summary` (default): Show truncated diffs and stats
- `ACTS_REVIEW_MODE=full`: Show complete file-by-file diffs

## Steps

1. **STAGE ALL CHANGES**
   Run `git add .` to stage all pending changes.

2. **CHECK REVIEW PROVIDER**
   - Check `ACTS_REVIEW_PROVIDER` env var or `acts.json` config
   - Auto-detect available tools (githuman → lazygit → manual)

3. **RUN REVIEW**
   
   **For GitHuman:**
   a. Launch GitHuman server on port 3847
   b. Display URL and review menu
   c. Wait for developer to review in browser
   d. Wait for developer to select menu option
   e. Export review from GitHuman
   f. Stop GitHuman server
   
   **For lazygit:**
   a. Launch lazygit TUI
   b. Wait for developer to exit lazygit
   c. Present approval menu
   
   **For Manual:**
   a. Show formatted diff output
   b. Present approval menu
   c. Wait for developer input

4. **HANDLE RESULT**
   
   IF approved:
   - Create review artifact with status "approved"
   - Archive to `.story/reviews/archive/`
   - Return success
   
   IF changes_requested:
   - Create review artifact with comments
   - Archive to `.story/reviews/archive/`
   - Return changes_requested status
   - Task remains IN_PROGRESS
   
   IF cancelled:
   - Return cancelled status
   - Task remains IN_PROGRESS

5. **UPDATE STATE** (handled by caller)
   Set in `state.json`:
   - `review_status`: "approved" | "changes_requested"
   - `reviewed_at`: ISO 8601 timestamp
   - `reviewed_by`: developer name

## Environment Variables

- `ACTS_REVIEW_PROVIDER`: Select review tool (`githuman`, `lazygit`, `manual`, `auto`)
- `ACTS_REVIEW_MODE`: Manual review display (`summary`, `full`)

## Exit Codes

- `0`: Review approved
- `1`: Error or cancelled
- `2`: Changes requested
- `3`: Manual review required (when no TTY available)

## Constraints

- This is a HARD GATE — agent MUST stop and wait for approval.
- There are no timeouts. Agent waits indefinitely.
- If review provider fails, fall back to manual review — do NOT skip the gate.
- The review artifact MUST be saved before the task can transition to DONE.
- If code_review is disabled, this entire operation is skipped.
- In non-interactive environments, uses file-based polling as fallback.

## Review Artifact Format

```markdown
# Review — <task_id>

- **Story:** <story_id>
- **Reviewer:** <developer name or tool>
- **Date:** <ISO 8601>
- **Status:** approved | changes_requested
- **Tool:** githuman | lazygit | manual

## Files Reviewed

- <file1>
- <file2>

## Comments

<review comments or "No comments provided">

## Stats

<git diff --stat output>
```

## Example Usage

```bash
# Run with default provider (auto-detect)
echo '{"inputs": {"task_id": "T001", "story_id": "S001"}}' | acts run task-review

# Force GitHuman
echo '{"inputs": {"task_id": "T001"}}' | ACTS_REVIEW_PROVIDER=githuman acts run task-review

# Force manual review with full diffs
echo '{"inputs": {"task_id": "T001"}}' | ACTS_REVIEW_PROVIDER=manual ACTS_REVIEW_MODE=full acts run task-review
```
