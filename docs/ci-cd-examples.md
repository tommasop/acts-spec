# CI/CD Integration Examples

How to integrate ACTS validation in your pipeline.

---

## GitHub Actions

```yaml
name: ACTS Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: npm install -g ajv-cli
      
      - name: Validate ACTS
        run: .acts/bin/acts-validate --json
```

---

## GitLab CI

```yaml
acts-validation:
  image: node:20
  script:
    - npm install -g ajv-cli
    - .acts/bin/acts-validate --json
  only:
    - merge_requests
    - main
```

---

## What Gets Validated

- AGENTS.md has required sections
- state.json is valid JSON
- Session files follow naming convention
- All required operations exist
- No DONE tasks with empty files_touched
- No IN_PROGRESS tasks without assignee

---

## Validation Output

```json
{"pass": 42, "fail": 0, "warn": 1}
```

Non-zero `fail` count = merge blocked.

---

## Without lazygit (CI-only)

If you don't want to install lazygit in CI:

```yaml
- name: Validate ACTS
  run: .acts/bin/acts-validate --json
  env:
    ACTS_NO_REVIEW_PROVIDER: true
```

This skips review provider availability checks.

---

## MCP Server Validation (Layer 7)

To verify the MCP server starts correctly in CI:

```yaml
- name: Validate MCP Server
  run: |
    cd .acts/mcp-server
    npm install
    npm run build
    node -e "
      const { spawn } = require('child_process');
      const server = spawn('node', ['dist/index.js']);
      const init = JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'ci',version:'1.0.0'}}}) + '\n';
      server.stdin.write(init);
      server.stdout.on('data', d => {
        const lines = d.toString().split('\n').filter(Boolean);
        for (const line of lines) {
          const msg = JSON.parse(line);
          if (msg.id === 1 && msg.result) {
            console.log('MCP server: OK — ' + msg.result.serverInfo.name + ' v' + msg.result.serverInfo.version);
            server.kill();
            process.exit(0);
          }
        }
      });
      setTimeout(() => { console.error('MCP server timeout'); process.exit(1); }, 5000);
    "
```

This verifies:
- MCP server builds successfully
- Server starts and responds to initialize handshake
- Capabilities are correctly advertised
