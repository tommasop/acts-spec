---
operation_id: task-review
layer: 6
required: true
triggers: "none (implicit at task completion)"
context_budget: 30000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
optional_inputs: []
preconditions:
  - "Changes MUST be staged (git add)"
  - "Code review provider MUST be available"
  - ".story/reviews/active/ directory MUST exist"
postconditions:
  - "Review status is 'approved'"
  - "Review exported to .story/reviews/active/"
  - "Task can proceed to completion"
---

# task-review

## Purpose

Mandatory code review gate before task completion. Ensures human review
of all staged changes before committing. Integrated with external review
tools via the Code Review Interface (Layer 6).

This operation runs **implicitly** at the end of `task-start` before
the completion commit.

## Steps

1. **CHECK PREREQUISITES**
   - Verify changes are staged: `git diff --cached --quiet` should fail
   - Verify code review is enabled in `.acts/acts.json`
   - Verify provider is available (e.g., `which githuman`)

2. **PRESENT REPORT**
   Present **Code Review** report per `.acts/report-protocol.md`:
   - Files changed (staged)
   - Line statistics (+/-)
   - Test results
   - Lint results
   - Review interface URL (if server started)

3. **START REVIEW SERVER**
   Execute provider's `serve` command:
   ```bash
   githuman serve --port 3847 --no-open
   ```
   
   Capture server URL (e.g., `http://localhost:3847`)

4. **GATE: review**
   Say: "Code review interface ready at {url}
   
   Review all staged changes. Add inline comments if needed.
   
   When complete, tell me the review status:
   - 'approved' — ready to commit
   - 'changes_requested' — I'll address and re-stage"
   
   WAIT for explicit status from developer.

5. **HANDLE STATUS**
   
   **If changes_requested:**
   - Stop review server
   - Present comments/issues from review
   - Agent addresses concerns
   - Re-stage changes
   - LOOP back to step 3
   
   **If approved:**
   - Continue to step 6
   
   **If other:**
   - Ask for clarification
   - Wait for valid status

6. **EXPORT REVIEW**
   Execute provider's `export` command:
   ```bash
   githuman export last --output .story/reviews/active/T1-<timestamp>-<dev>.md
   ```
   
   Verify export succeeded.

7. **UPDATE INDEX**
   Append to `.story/reviews/index.md`:
   ```markdown
   - [T1](active/T1-20260328-101500-alice.md) — alice — approved — 2026-03-28
   ```

8. **CONFIRM**
   Say: "Code review complete. Task {task_id} approved and ready to commit."

## Constraints

- MUST NOT proceed without explicit approval
- MUST preserve all review versions (even if changes requested multiple times)
- MUST export review before task completion commit
- Review interface MUST be accessible (localhost or as configured)
- If provider unavailable, operation MUST fail with clear error

## Error Handling

**Provider not installed:**
```
❌ GitHuman not found

Install: npm install -g githuman

Or disable code review in .acts/acts.json:
{
  "code_review": { "enabled": false }
}
```

**No staged changes:**
```
❌ No staged changes to review

Stage changes first:
git add <files>
```

**Review server fails:**
```
❌ Failed to start review server
Error: <error message>

Check:
- Port 3847 is available
- GitHuman is properly installed
```
