# Example: Working on an Existing Project with ACTS v2

This document shows a complete agent interaction for joining an existing ACTS v2 project and continuing work.

---

## Scenario

**Project:** E-commerce platform (existing ACTS v2 project)
**Stack:** `cart` — "Add shopping cart"
**Previous work:** c1 (Cart model) and c2 (Cart API) are MERGED
**Current change:** c3 — "Add cart frontend component"
**Developer:** bob
**Tool:** Cursor (manual CLI approach)

---

## Step 1: Read Stack State

**User:** "Continue work on the shopping cart stack. I'm taking over from alice."

**Agent:**
```
Let me read the current stack state to understand what's been done.

> acts stack status

Stack: cart — Add shopping cart
  feature: acts/cart/feature (off master)
  PR: https://github.com/you/ecommerce/pull/21
  [x] MERGED  Cart model
  [x] MERGED  Cart API endpoints
  [ ] IN_PROGRESS  Cart frontend component
```

---

## Step 2: Load the Context Pack

**Agent:**
```
Let me load the durable context pack for c3.

> acts context c3

# ACTS Context Pack

## Stack
- id: cart
- title: Add shopping cart
- feature branch: acts/cart/feature

## Change: c3
- title: Cart frontend component
- status: IN_PROGRESS
- checkpoint: on feature branch acts/cart/feature

## Acceptance Criteria
- Cart.jsx renders cart items with quantities
- Add/remove item buttons call existing API
- Show total price

## Preceding Changes
- c1: Cart model (MERGED)
- c2: Cart API endpoints (MERGED)

## Session Notes
- .acts/changes/c3/notes/1785920000.md

## Changed Files
- src/components/Cart.jsx
- src/components/Cart.test.jsx
```

**Agent:**
```
From alice's notes:
- Cart model supports: addItem, removeItem, getCart, clearCart
- API endpoints: POST /cart/items, DELETE /cart/items/:id, GET /cart
- All tests passing
```

---

## Step 3: Check Scope

**Agent:**
```
Let me verify the files I'll touch belong to this change's diff.

> acts scope c3 src/components/Cart.jsx

{
  "file_path": "src/components/Cart.jsx",
  "action": "ok",
  "message": "File is part of change c3's diff"
}
```

**Agent:**
```
I should NOT modify c1's model files or c2's route files — those belong to
their own diffs. If I need to touch them, I'd coordinate with their owners
or open a new change.

> acts scope c3 src/models/cart.js

{
  "file_path": "src/models/cart.js",
  "action": "warn",
  "message": "File not in change c3's diff — verify it belongs to this task before editing"
}
```

---

## Step 4: Implement c3

**Agent:** [Implements code on the feature branch — its commits become c3's checkpoint range]

```
Creating src/components/Cart.jsx...
Creating src/components/Cart.test.jsx...

> Bash: npm test -- Cart.test.jsx
Tests passing: 8/8
```

---

## Step 5: Verify

**Agent:**
```
> acts verify c3

  test: PASS (npm test) [107ms]
  lint: PASS (npm run lint) [99ms]
  build: PASS (npm run build) [135ms]
change c3 verified
```

---

## Step 6: Review (the stack's ONE PR)

**Agent:**
```
> acts review c3

PR for stack cart submitted: https://github.com/you/ecommerce/pull/21
```

The PR body includes the context pack: acceptance criteria, verification evidence, and notes. This is the stack's ONE PR (feature → master). Bob (or a reviewer) reviews on GitHub.

---

## Step 7: Record Session State

**Agent:**
```
Recording session summary:

> acts note c3 -m "Created Cart.jsx + tests; used existing cart API from c2; did not modify model files (c1)"
note appended to c3

> acts checkpoint c3 -s "done: cart component; blocked: none; next: PR review"
checkpoint recorded for c3

> acts validate
manifest OK
```

---

## Step 8: Approve & Land (after human review)

**User:** "Approved on GitHub."

**Agent:**
```
> acts approve c3
change c3 approved

> acts stack land
merged feature branch acts/cart/feature into master; PR closed
```

---

## Key Points for Existing Projects

### What the agent did right:
1. ✅ Read stack state first (`acts stack status`)
2. ✅ Loaded the context pack (`acts context c3`) — acceptance criteria, preceding changes, notes
3. ✅ Checked file ownership (`acts scope c3 <file>`)
4. ✅ Respected merged-change boundaries (didn't modify c1/c2 files)
5. ✅ Verified quality gates before review (`acts verify c3`)
6. ✅ Submitted the stack's ONE PR (`acts review c3`)
7. ✅ Recorded note + checkpoint (`acts note` / `acts checkpoint`)

### What could have gone wrong:
- Without `acts stack status`: Agent might not know c1/c2 are merged
- Without `acts context c3`: Agent might miss acceptance criteria or prior session notes
- Without `acts scope`: Agent might modify files owned by other changes' diffs

---

## Summary

In this session:
1. ✅ Read current stack state
2. ✅ Loaded the c3 context pack (durable task state)
3. ✅ Checked file ownership via `acts scope`
4. ✅ Implemented c3 while respecting existing change boundaries
5. ✅ Verified quality gates → submitted the stack's ONE PR
6. ✅ Recorded note + checkpoint, ran `acts validate`

**Next:** After PR approval, `acts approve c3` + `acts stack land`.
