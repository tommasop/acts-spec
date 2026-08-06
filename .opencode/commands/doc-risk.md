---

description: Evaluate the risk of a spec or plan document, grounded in the codebase via CBM
agent: build

---

Evaluate the risk of a spec or plan document, highlighting the major painpoints.

Usage: `/doc-risk <file>`

- `<file>` is a local `.md`/`.txt` path or a remote URL.
- Runs `acts doc-risk <file>` — static heuristic analysis (ambiguity, scope, tech-debt, integration, concurrency, security, testability) merged with CBM code-intelligence (cross-repo edges, hotspots, complexity, unresolved references).

Interpret the report for the user:
- Overall risk tier + worst category
- Top painpoints (static and code-intelligence)
- Unresolved references (plan mentions code not found in the graph)
- Suggested actions (resolve ambiguity before sequencing, spike for migration, etc.)
