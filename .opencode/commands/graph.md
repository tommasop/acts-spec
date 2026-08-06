---

description: CBM fleet helpers — list repos, index, bootstrap, and map a change to its repos
agent: build

---

CBM (codebase-memory-mcp) fleet helpers, exposed as `acts graph` subcommands (CBM tools themselves come via the native MCP server).

Usage: `/graph <subcommand> [args]`

- `repos` — list fleet repositories from `opencode.json` references
- `index --all` — index every reference into the shared graph
- `bootstrap` — idempotent install+index (CI / fresh machines)
- `span <id>` — map a change's files to the repos it spans

Run via the `acts` tool: `acts graph $ARGUMENTS`.
