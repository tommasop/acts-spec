---
operation_id: commit-review
layer: 6
required: false
triggers: "none (explicit user request)"
context_budget: 20000
required_inputs:
  - name: commit_range
    type: string
    required: true
    description: "Git commit range to review (e.g., 'HEAD~3..HEAD')"
optional_inputs:
  - name: reviewer
    type: string
    required: false
    description: "Specific reviewer (defaults to current developer)"
preconditions:
  - "Commit range MUST exist"
  - "Code review provider MUST be available"
postconditions:
  - "Review completed and exported"
  - "Review does NOT block anything (informational)"
---

# commit-review

## Purpose

Explicit code review of specific commits. Used for:
- Reviewing partial work mid-task
- Reviewing multiple commits at once
- Retroactive review of existing commits
- Peer review requests

Unlike `task-review`, this operation is **explicit** (user-initiated) and
**informational** (does not gate task completion).

## Steps

1. **VERIFY INPUTS**
   - Validate commit range exists: `git log {commit_range}`
   - Verify provider is available

2. **CHECKOUT COMMITS**
   ```bash
   git checkout {commit_range_end}
   ```
   
   Or create temporary worktree for review.

3. **PRESENT REPORT**
   Present **Code Review** report:
   - Commits in range
   - Files changed
   - Diff statistics
   - Review interface URL

4. **START REVIEW SERVER**
   Start provider server for commit range.

5. **GATE: approve** (informational)
   Say: "Reviewing commits {commit_range}
   
   Review interface: {url}
   
   This is an informational review — no action required.
   Type 'yes' when done reviewing."
   Comments and findings will be saved for reference.
   
   Tell me when review is complete."
   
   Wait for completion signal.

6. **EXPORT REVIEW**
   Export to `.story/reviews/archive/commits/`:
   ```
   .story/reviews/archive/commits/
   └── 20260328-101500-<range>-<dev>.md
   ```

7. **RETURN TO BASE**
   Checkout original branch.

8. **SUMMARIZE**
   Present review summary and file location.

## Usage Examples

**Review last 3 commits:**
```
User: Review commits HEAD~3..HEAD
Agent: [runs commit-review]
```

**Review specific range:**
```
User: Review commits abc123..def456
Agent: [runs commit-review]
```

**Review for peer:**
```
User: Review commits HEAD~2..HEAD and assign to bob
Agent: [runs commit-review, notes bob as reviewer]
```
