# Example: Working on an Existing Project with ACTS

This document shows a complete agent interaction for joining an existing ACTS project and continuing work.

---

## Scenario

**Project:** E-commerce platform (existing ACTS project)
**Story:** PROJ-305 — "Add shopping cart"
**Previous work:** T1 (Setup cart model) and T2 (Add cart API) are DONE
**Current task:** T3 — "Add cart frontend component"
**Developer:** bob
**Tool:** Cursor (manual CLI approach)

---

## Step 1: Read Project State

**User:** "Continue work on the shopping cart story. I'm taking over from alice."

**Agent:**
```
Let me read the current project state to understand what's been done.

> acts state read

{
  "story_id": "PROJ-305",
  "title": "Add shopping cart",
  "status": "IN_PROGRESS",
  "tasks": [
    {
      "id": "T1",
      "title": "Setup cart model",
      "status": "DONE",
      "assigned_to": "alice",
      "files_touched": ["src/models/cart.js", "src/models/cart.test.js"]
    },
    {
      "id": "T2",
      "title": "Add cart API endpoints",
      "status": "DONE",
      "assigned_to": "alice",
      "files_touched": ["src/routes/cart.js", "src/routes/cart.test.js"]
    },
    {
      "id": "T3",
      "title": "Add cart frontend component",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": ["T1", "T2"]
    }
  ]
}
```

---

## Step 2: Check Ownership

**Agent:**
```
Let me check which files are owned by completed tasks:

> acts ownership map

{
  "T1": {
    "status": "DONE",
    "files": ["src/models/cart.js", "src/models/cart.test.js"]
  },
  "T2": {
    "status": "DONE",
    "files": ["src/routes/cart.js", "src/routes/cart.test.js"]
  }
}
```

**Agent:**
```
I'll read the completed tasks' files to understand the existing code:

> Read src/models/cart.js
> Read src/routes/cart.js
> Read .story/sessions/20260104-100000-alice.md

From alice's last session:
- Cart model supports: addItem, removeItem, getCart, clearCart
- API endpoints: POST /cart/items, DELETE /cart/items/:id, GET /cart
- All tests passing
```

---

## Step 3: Start T3

**Agent:**
```
Let me check the scope for T3 before starting:

> acts scope check --task T3 --file src/components/Cart.jsx

{
  "file_path": "src/components/Cart.jsx",
  "action": "ok",
  "message": "File is not owned by any other task. Safe to modify."
}

Good, I can create this file. Let me also check other files I might need:

> acts scope check --task T3 --file src/models/cart.js

{
  "file_path": "src/models/cart.js",
  "action": "error",
  "message": "File is owned by DONE task T1. Modifications require explicit approval."
}
```

**Agent:**
```
I need to be careful — I can create new frontend files but should not modify T1's model files without approval. Let me add the preflight gate:

> acts gate add --task T3 --type approve --status approved --by bob
> acts task update T3 --status IN_PROGRESS --assigned-to bob

Task T3 is now IN_PROGRESS.
```

---

## Step 4: Read Plan Entry

**Agent:**
```
Let me read the plan to understand what T3 should do:

> Read .story/plan.md

### T3: Add cart frontend component
- Create Cart.jsx React component
- Display cart items with quantities
- Add/remove item buttons
- Show total price
- Files: src/components/Cart.jsx, src/components/Cart.test.jsx
```

---

## Step 5: Check Dependencies

**Agent:**
```
T3 depends on T1 and T2. Let me verify they're DONE:

> acts task get T1
{ "id": "T1", "status": "DONE", ... }

> acts task get T2
{ "id": "T2", "status": "DONE", ... }

Both dependencies are complete. I can proceed.
```

---

## Step 6: Implement T3

**Agent:** [Implements code]

```
Creating src/components/Cart.jsx...
Creating src/components/Cart.test.jsx...

> Bash: npm test -- Cart.test.jsx
Tests passing: 8/8
```

---

## Step 7: Complete T3

**Agent:**
```
Task T3 is complete. Let me run validation and update state:

> Bash: npm test
All tests passing: 24/24

> Bash: npm run lint
Lint clean

> acts gate add --task T3 --type task-review --status approved --by bob
> acts task update T3 --status DONE

Task T3 is now DONE.
```

---

## Step 8: Record Session Summary

**Agent:**
```
Recording session summary:

> Write .story/sessions/20260105-160000-bob.md

# Session Summary
- **Developer:** bob
- **Agent:** Cursor (Claude-3.5-Sonnet)
- **Date:** 2026-01-05T16:00:00Z
- **Task:** T3 — Add cart frontend component

## What was done
- Created Cart.jsx React component with:
  - Display cart items with quantities
  - Add/remove item buttons
  - Total price calculation
- Created Cart.test.jsx with 8 tests
- All tests passing (24/24 total)
- Lint clean

## Decisions made
- Used React hooks (useState, useEffect) for state management
- Called existing cart API endpoints (from T2)
- Did NOT modify cart model (T1) — used existing API instead

## What was NOT done (and why)
- No checkout flow (out of scope for this story)
- No persistent cart across sessions (deferred to future story)

## Approaches tried and rejected
- Considered modifying cart model to add frontend-specific fields
- Rejected: Would violate ownership (T1 is DONE)
- Instead: Added needed data to API response (coordinated with alice)

## Open questions
- Should cart persist for logged-out users?
- Do we need optimistic updates for better UX?

## Current state
- Compiles: ✅
- Tests pass: ✅ 24/24
- Uncommitted work: ✅

## Files touched this session
- src/components/Cart.jsx — new cart component
- src/components/Cart.test.jsx — component tests

## Suggested next step
Start T4: Add checkout flow (if it exists) or create new story for checkout

## Agent Compliance
- Read state before writing code: ✅ (acts state read)
- Did not modify files owned by DONE tasks: ✅
  - Checked scope: src/models/cart.js is owned by T1
  - Used existing API instead of modifying model
- Stayed within assigned task boundary: ✅
- Followed context protocol: ✅
  - Read completed task files (T1, T2)
  - Read previous session summary
  - Read plan entry for T3
```

---

## Step 9: Validate and Verify

**Agent:**
```
> acts session validate .story/sessions/20260105-160000-bob.md
Session validation passed

> acts validate
Schema version: 1
Found: .story/plan.md
Found: .story/spec.md
Session files: 2
Validation PASSED

> acts ownership map
{
  "T1": {
    "status": "DONE",
    "files": ["src/models/cart.js", "src/models/cart.test.js"]
  },
  "T2": {
    "status": "DONE",
    "files": ["src/routes/cart.js", "src/routes/cart.test.js"]
  },
  "T3": {
    "status": "DONE",
    "files": ["src/components/Cart.jsx", "src/components/Cart.test.jsx"]
  }
}
```

---

## Key Points for Existing Projects

### What the agent did right:
1. ✅ Read state first (`acts state read`)
2. ✅ Checked file ownership (`acts ownership map`)
3. ✅ Verified dependencies are DONE before starting
4. ✅ Checked scope before modifying files (`acts scope check`)
5. ✅ Respected DONE task ownership (didn't modify T1's files)
6. ✅ Read previous session summaries for context
7. ✅ Read completed task files to understand existing code
8. ✅ Added preflight gate before starting task
9. ✅ Added task-review gate before marking DONE

### What could have gone wrong:
- Without `acts state read`: Agent might not know T1/T2 are DONE
- Without `acts ownership map`: Agent might modify T1's model files
- Without `acts scope check`: Agent might unknowingly violate ownership
- Without gates: Task status could be changed without approval

---

## Summary

In this session:
1. ✅ Read current project state
2. ✅ Checked file ownership before making changes
3. ✅ Verified dependencies (T1, T2) are DONE
4. ✅ Completed T3 while respecting existing ownership
5. ✅ Recorded and validated session summary
6. ✅ All gates enforced correctly

**Next:** Story is now 3/3 tasks DONE. Can proceed to story review or start new story.
