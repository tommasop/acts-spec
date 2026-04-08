---
operation_id: compress-sessions
layer: 3
required: false
triggers: "none"
context_budget: 100000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: keep_latest
    type: integer
    required: false
    default: 3
optional_inputs: []
preconditions:
  - "At least 5 session summaries exist for the target task"
  - "The compressed file does NOT already exist (or developer confirms overwrite)"
postconditions:
  - "Compressed file contains merged decisions, approaches, and open questions"
  - "Original session files are preserved"
  - "state.json compressed flag is set"
---

# compress-sessions

## Purpose

Merge older session summaries for a task into a single compressed
briefing file, reducing context load for long-running stories while
preserving critical information (decisions, rejected approaches,
open questions).

## Steps

1. **READ ALL SESSIONS**
   Find all session summaries for the task in chronological order.
   
   If fewer than 5 sessions:
   Say: "Only <N> sessions found. Compression recommended at 5+."
   Present count, ask if user wants to proceed anyway.

2. **SPLIT SESSIONS**
   - Keep the latest `keep_latest` sessions untouched.
   - The remaining sessions will be compressed.

3. **EXTRACT AND MERGE**
   For sessions to compress:
   
   a. **Decisions made** — deduplicate, note date range
   b. **Approaches tried and rejected** — KEEP ALL (never compress)
   c. **Open questions** — mark resolved ones, keep unresolved
   d. **Files touched** — union into one list
   e. **What was NOT done** — merge remaining items

4. **WRITE COMPRESSED FILE**
   Create `.story/sessions/compressed-<task_id>.md`:
   
   ```markdown
   # Compressed Session Summary: <task_id>
   
   > **WARNING:** This is a compressed summary, not original session data.
   > Original files are preserved in `.story/sessions/`.
   > Sessions merged: <list of filenames and dates>
   
   ## Decisions Made (merged from <N> sessions)
   <deduplicated decisions with date ranges>
   
   ## Approaches Tried and Rejected (PRESERVED IN FULL)
   <EVERY rejected approach from all sessions>
   
   ## Open Questions (status as of <date>)
   <merged and marked>
   
   ## Files Touched (union)
   <all files from compressed sessions>
   
   ## What Was NOT Done (remaining)
   <merged remaining work>
   ```

5. **PRESENT SUMMARY**
   Show:
   - Total sessions: <N>
   - Kept (uncompressed): <keep_latest>
   - Compressed: <N - keep_latest>
   - File written: compressed-<task_id>.md

6. **UPDATE STATE**
   - `state.json` → `compressed: true`
   - `updated_at` → now

7. **COMMIT**
   `chore(<story_id>): compress sessions for <task_id>`

## Constraints

- "Approaches tried and rejected" is NEVER compressed.
- Original session files are NOT deleted.
- The compressed file MUST clearly state it is a compression.
- Recommended when session_count exceeds 10 for a single task.
