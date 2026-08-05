# Example: Starting a New Project with ACTS v2

This document shows a complete agent interaction for bootstrapping a new project with ACTS v2.

---

## Scenario

**Project:** Build a URL shortener API
**Stack:** `urlshort` — "URL Shortener Service"
**Developer:** alice
**Tool:** OpenCode with the ACTS plugin

---

## Step 1: Start the Stack

**User:** "Set up ACTS for a new project called 'url-shortener'"

**Agent:**
```
I'll start a new ACTS stack for your project.

> acts stack create urlshort -t "URL Shortener Service"

stack urlshort created on branch acts/urlshort/base
```

**Result:**
- Base branch `acts/urlshort/base` created off `main`
- `.acts/stack.json` manifest created (empty changes)

---

## Step 2: Plan the Changes

**User:** "Plan the work. We need:
- POST /shorten with a URL, return a short code
- Redirect GET /:code to the original URL
- Track click counts
- Expire URLs after 30 days"

**Agent:**
```
I'll break this into changes along the dependency chain.

> acts change add c1 -t "Setup project structure" --accept "Node.js + Express project scaffolds"
> acts change add c2 -t "POST /shorten endpoint" --accept "POST /shorten returns {shortCode}"
> acts change add c3 -t "GET /:code redirect" --accept "301 redirect + click increment"
> acts change add c4 -t "URL expiration" --accept "URLs expire after 30 days"

change c1 added on branch acts/urlshort/c1-setup-project-structure
change c2 added on branch acts/urlshort/c2-post-shorten-endpoint (parent: c1)
change c3 added on branch acts/urlshort/c3-get-code-redirect (parent: c2)
change c4 added on branch acts/urlshort/c4-url-expiration (parent: c3)
```

---

## Step 3: Work a Change

**User:** "Start on c1 — scaffold the project"

**Agent:**
```
Let me load the context pack for c1 first.

> acts_context (change_id: c1)

# ACTS Context Pack
## Change: c1
- title: Setup project structure
- status: TODO
- branch: acts/urlshort/c1-setup-project-structure

## Acceptance Criteria
- Node.js + Express project scaffolds
```

**Agent:** [Implements code using Write/Edit tools on the c1 branch]

```
Creating package.json...
Creating src/server.js...

> Bash: npm install express
> Bash: node src/server.js
Server running on port 3000
```

---

## Step 4: Verify

**Agent:**
```
Time to run the quality gates.

> acts verify c1

  test: PASS (npm test) [107ms]
  lint: PASS (npm run lint) [99ms]
  build: PASS (npm run build) [135ms]
change c1 verified
```

---

## Step 5: Review (Stacked PR)

**Agent:**
```
> acts review c1

PR submitted: https://github.com/you/url-shortener/pull/3
```

The PR body contains the context pack: acceptance criteria, verification evidence, and the change's notes.

---

## Step 6: Approve & Land

**User:** "Approved. Land it."

**Agent:**
```
> acts approve c1
change c1 approved

> acts stack land
landed c1 onto acts/urlshort/base
```

---

## Step 7: Record Session State

**Agent:**
```
Recording session summary:

> acts note c1 -m "Scaffolded Node.js + Express; verified server starts"
note appended to c1

> acts checkpoint c1 -s "done: scaffold; next: c2 POST /shorten"
checkpoint recorded for c1

> acts validate
manifest OK
```

---

## Summary

In this session:
1. ✅ Started a stack with `acts stack create`
2. ✅ Planned 4 changes with `acts change add`
3. ✅ Loaded context with `acts_context` before coding
4. ✅ Verified c1 with `acts verify` (evidence recorded)
5. ✅ Submitted a stacked PR with `acts review`
6. ✅ Approved + landed with `acts approve` + `acts stack land`
7. ✅ Recorded note/checkpoint + `acts validate`

**Next:** Work c2 (POST /shorten endpoint).
