---
description: Load Magic usage rules — all by default, or specific rules by name (/usage-rules core, /usage-rules error-handling)
agent: build
---

Load the Magic platform usage rules and treat them as binding for this session.

Requested rules: $ARGUMENTS (empty = load ALL)

Resolve the rules directory from the first that exists:
1. `deps/magic/usage-rules/` — magic dependency compiled in this project
2. `usage-rules/` — working inside the magic library source

!`sh -c 'd="deps/magic/usage-rules"; [ -d "$d" ] || d="usage-rules"; if [ -z "$*" ]; then cat "$d"/*.md 2>/dev/null; else for n in "$@"; do case "$n" in core) cat "$d"/coding-practices.md "$d"/error-handling.md 2>/dev/null ;; *) cat "$d/$n.md" 2>/dev/null || echo "(no such magic rule: $n)" ;; esac; done; fi' __ $ARGUMENTS`

If the shell output above is empty, no magic usage rules were found in this project — state that and stop. If specific rule names were requested and their content is missing above, Read each `<name>.md` from the resolved directory with your Read tool.

Valid rule names: architecture, authentication, authorization, casbin, coding-practices, error-handling, logging, openapi, plug-patterns, saga_services. `core` loads coding-practices + error-handling.