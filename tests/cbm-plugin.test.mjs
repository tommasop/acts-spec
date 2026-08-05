// Offline test for the cbm.js OpenCode plugin (ACTS v2 — git-native).
// Spins up a temp project with a dummy `codebase-memory-mcp` binary and an
// ACTS v2 `.acts/stack.json` manifest so we can assert tool registration,
// reference loading, path resolution, and the ACTS↔repo scope bridge
// without network or the real CBM binary.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import assert from 'assert';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, '..', '.opencode', 'plugins', 'cbm.js');

let passed = 0;
const ok = (name) => { passed++; console.log(`  ✓ ${name}`); };

// ── Build a temp project ────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cbm-test-'));
const binDir = path.join(tmp, '.acts', 'bin');
fs.mkdirSync(binDir, { recursive: true });
fs.mkdirSync(path.join(tmp, 'repos', 'ui-payments', 'src'), { recursive: true });
fs.mkdirSync(path.join(tmp, 'repos', 'magic', 'lib'), { recursive: true });

fs.writeFileSync(path.join(tmp, 'opencode.json'), JSON.stringify({
  references: {
    'ui-payments': { path: 'repos/ui-payments', description: 'Payments UI' },
    'magic': { path: 'repos/magic', description: 'Magic core' },
  },
}));

// ACTS v2 manifest (git-native coordination state)
fs.writeFileSync(path.join(tmp, '.acts', 'stack.json'), JSON.stringify({
  version: 2,
  id: 'auth',
  title: 'User auth',
  base_branch: 'acts/auth/base',
  changes: [
    { id: 'c1', title: 'JWT middleware', status: 'IN_PROGRESS', branch: 'acts/auth/c1-jwt' },
    { id: 'c2', title: 'Login endpoint', status: 'TODO', branch: 'acts/auth/c2-login' },
  ],
}, null, 2));

// Dummy CBM binary: echoes its args (handler returns stdout).
const cbmBin = path.join(binDir, 'codebase-memory-mcp');
fs.writeFileSync(cbmBin, `#!/usr/bin/env bash\necho "CBM_CALLED:$@"\n`);
fs.chmodSync(cbmBin, 0o755);

const cleanup = () => fs.rmSync(tmp, { recursive: true, force: true });

try {
  const { CbmPlugin } = await import(pluginPath);
  const client = { app: { log: async () => {} } };
  const hooks = await CbmPlugin({ client, directory: tmp });

  // 1. Plugin shape
  assert.ok(typeof hooks.tools === 'function', 'plugin returns tools()');
  assert.ok(typeof hooks['experimental.chat.system.transform'] === 'function', 'plugin returns system transform hook');
  ok('plugin exposes tools() and system-transform hooks');

  const tools = await hooks.tools();

  // 2. Native CBM tools registered
  const native = ['index_repository', 'list_projects', 'delete_project', 'index_status',
    'search_graph', 'trace_path', 'detect_changes', 'query_graph', 'get_graph_schema',
    'get_code_snippet', 'get_architecture', 'search_code', 'manage_adr', 'ingest_traces'];
  for (const n of native) {
    assert.ok(tools[n] && typeof tools[n].handler === 'function', `missing native tool: ${n}`);
  }
  ok(`all 14 native CBM tools registered (${native.length})`);

  // 3. Fleet helpers + ACTS bridge
  for (const n of ['cbm_repos', 'cbm_index_all', 'cbm_changes', 'cbm_bootstrap', 'cbm_install', 'acts_memory']) {
    assert.ok(tools[n] && typeof tools[n].handler === 'function', `missing tool: ${n}`);
  }
  ok('fleet helpers (incl. cbm_bootstrap) + acts_memory bridge registered');

  // 4. cbm_repos lists references with resolved paths
  const repos = await tools.cbm_repos.handler({});
  assert.ok(repos.content[0].text.includes('ui-payments'), 'cbm_repos shows ui-payments');
  assert.ok(repos.content[0].text.includes(path.join(tmp, 'repos', 'ui-payments')), 'cbm_repos shows resolved path');
  ok('cbm_repos lists references + resolved paths');

  // 5. cbm_index_all calls the binary with resolved repo paths (verifies resolveRefPath + runCbm)
  const idx = await tools.cbm_index_all.handler({});
  const idxText = idx.content[0].text;
  assert.ok(idxText.includes('CBM_CALLED'), 'cbm_index_all invoked the binary');
  assert.ok(idxText.includes('index_repository'), 'cbm_index_all passed index_repository');
  assert.ok(idxText.includes(path.join(tmp, 'repos', 'ui-payments')), 'cbm_index_all resolved ui-payments path');
  assert.ok(idxText.includes(path.join(tmp, 'repos', 'magic')), 'cbm_index_all resolved magic path');
  ok('cbm_index_all indexes every reference with resolved paths');

  // 6. ACTS bridge: acts_memory scope reads the v2 manifest (change c1 exists)
  const scope = await tools['acts_memory'].handler({ command: 'scope c1' });
  const scopeText = scope.content[0].text;
  assert.ok(scopeText.includes('c1'), 'scope shows change id');
  assert.ok(scopeText.includes('JWT middleware'), 'scope shows change title');
  assert.ok(scopeText.includes('IN_PROGRESS'), 'scope shows change status');
  ok('acts_memory scope reads ACTS v2 manifest change');

  // 6b. Unknown change returns a clear error
  const missing = await tools['acts_memory'].handler({ command: 'scope nope' });
  assert.ok(missing.content[0].text.includes('not found'), 'scope reports unknown change');
  ok('acts_memory scope reports unknown change');

  // 7. System context includes cross-repo block + per-change span
  const out = { system: [] };
  await hooks['experimental.chat.system.transform']({}, out);
  const ctx = out.system.join('\n');
  assert.ok(ctx.includes('Cross-Repo Memory'), 'system context has cross-repo block');
  assert.ok(ctx.includes('ui-payments'), 'system context lists fleet repos');
  ok('system context injects cross-repo block');

  console.log(`\n${passed} checks passed.`);
  cleanup();
} catch (e) {
  cleanup();
  console.error('\nTEST FAILED:', e.message);
  process.exit(1);
}
