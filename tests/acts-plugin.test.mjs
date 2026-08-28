// Offline test for the acts.js OpenCode plugin (ACTS v2 — git-native).
// Spins up a temp project with a dummy `acts` binary (echoes args) and an
// ACTS v2 `.acts/stack.json` manifest so we can assert tool registration,
// context injection, and binary discovery without the real binary.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import assert from 'assert';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, '..', '.opencode', 'plugins', 'acts.js');

let passed = 0;
const ok = (name) => { passed++; console.log(`  ✓ ${name}`); };

// ── Build a temp project ────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'acts-plugin-test-'));
const binDir = path.join(tmp, '.acts', 'bin');
fs.mkdirSync(binDir, { recursive: true });

// ACTS v2 manifest
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

// Dummy acts binary: echoes args so we can assert what the plugin invokes,
// and returns valid stack JSON for `stack status --json`. Reports a v2 version
// so the plugin's version-aware discovery picks it over any global binary.
const actsBin = path.join(binDir, 'acts');
fs.writeFileSync(actsBin, `#!/usr/bin/env bash
if [ "$1" = "version" ]; then
  echo "acts 2.99.0"
  exit 0
fi
if [ "$1" = "stack" ] && [ "$2" = "status" ] && [ "$3" = "--json" ]; then
  echo '{"version":2,"id":"auth","title":"User auth","base_branch":"acts/auth/base","changes":[{"id":"c1","title":"JWT middleware","status":"IN_PROGRESS","branch":"acts/auth/c1-jwt"},{"id":"c2","title":"Login endpoint","status":"TODO","branch":"acts/auth/c2-login"}]}'
  exit 0
fi
echo "ACTS_CALLED:$@"
`);
fs.chmodSync(actsBin, 0o755);

const cleanup = () => fs.rmSync(tmp, { recursive: true, force: true });

try {
  const { ActsPlugin } = await import(pluginPath);
  const hooks = await ActsPlugin({ directory: tmp });

  // 1. Plugin shape
  assert.ok(typeof hooks.tools === 'function', 'plugin returns tools()');
  assert.ok(typeof hooks['experimental.chat.system.transform'] === 'function', 'plugin returns system transform hook');
  assert.ok(typeof hooks['experimental.chat.messages.transform'] === 'function', 'plugin returns messages transform hook');
  ok('plugin exposes tools() + transform hooks');

  const tools = await hooks.tools();

  // 2. Core tools registered
  for (const n of ['acts', 'acts_context', 'acts_mode', 'acts_zeplin', 'acts_archify']) {
    assert.ok(tools[n] && typeof tools[n].handler === 'function', `missing tool: ${n}`);
  }
  ok('acts / acts_context / acts_mode / acts_zeplin / acts_archify tools registered');

  // 3. acts tool passes command through to binary
  const res = await tools.acts.handler({ command: 'verify c1' });
  assert.ok(res.content[0].text.includes('ACTS_CALLED'), 'acts tool invoked binary');
  assert.ok(res.content[0].text.includes('verify c1'), 'acts tool passed command verbatim');
  ok('acts tool runs commands via binary');

  // 4. acts_context resolves change id
  const ctx = await tools.acts_context.handler({ change_id: 'c1' });
  assert.ok(ctx.content[0].text.includes('ACTS_CALLED:context c1'), 'acts_context passes context <id>');
  ok('acts_context emits context pack for a change');

  // 5. acts_zeplin returns a helpful error when the contract script is absent (offline)
  const zp = await tools.acts_zeplin.handler({ url: 'https://app.zeplin.io/project/abc/flow/xyz' });
  assert.ok(zp.content[0].text.includes('acts-zeplin-contract.mjs'), 'acts_zeplin references the contract script');
  ok('acts_zeplin handles missing script gracefully offline');

  // 5b. acts_archify returns a helpful install hint when the renderer is absent (offline)
  const ar = await tools.acts_archify.handler({ action: 'validate', type: 'architecture', input: 'ir.json' });
  assert.ok(ar.content[0].text.includes('archify'), 'acts_archify mentions archify');
  assert.ok(ar.content[0].text.includes('acts archify install'), 'acts_archify suggests installing the renderer');
  ok('acts_archify handles missing renderer gracefully offline');

  // 6. System context includes stack info from manifest + auto-injects active change pack
  const out = { system: [] };
  await hooks['experimental.chat.system.transform']({}, out);
  const sys = out.system.join('\n');
  assert.ok(sys.includes('auth'), 'system context has stack id');
  assert.ok(sys.includes('JWT middleware'), 'system context lists changes');
  assert.ok(sys.includes('Active Change'), 'system context auto-injects the active change pack');
  ok('system transform injects v2 stack context + auto-injects active change');

  // 6b. acts_context with blast_radius falls back gracefully when no CBM binary
  const ctxBr = await tools.acts_context.handler({ change_id: 'c1', blast_radius: true });
  assert.ok(ctxBr.content[0].text.includes('ACTS_CALLED:context c1'), 'acts_context still returns the context pack');
  ok('acts_context with blast_radius degrades gracefully offline');

  // 7. Bootstrap injected into first user message
  const msg = { messages: [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hello' }] }] };
  await hooks['experimental.chat.messages.transform']({}, msg);
  const first = msg.messages[0].parts[0].text;
  assert.ok(first.includes('ACTS v2'), 'bootstrap mentions ACTS v2');
  assert.ok(first.includes('acts context'), 'bootstrap includes v2 commands');
  ok('bootstrap injected into first user message');

  // 9. Version-aware binary discovery: a stale v1 project-local binary is
  //    skipped in favor of a v2 global binary on PATH (regression: v1 shadows
  //    v2 and auto-creates a SQLite db). Here the local binary reports v1 and
  //    the global (earlier on PATH) reports v2 — the tool must call the v2 one.
  const v1dir = fs.mkdtempSync(path.join(os.tmpdir(), 'acts-v1shadow-'));
  fs.mkdirSync(path.join(v1dir, '.acts', 'bin'), { recursive: true });
  fs.writeFileSync(path.join(v1dir, '.acts', 'stack.json'), JSON.stringify({
    version: 2, id: 's', title: 's', base_branch: 'acts/s/base', changes: [],
  }));
  fs.writeFileSync(path.join(v1dir, '.acts', 'bin', 'acts'), `#!/usr/bin/env bash
if [ "$1" = "version" ]; then echo "acts 1.2.0"; exit 0; fi
echo "V1_CALLED:$@"
`);
  fs.chmodSync(path.join(v1dir, '.acts', 'bin', 'acts'), 0o755);

  const globalDir = fs.mkdtempSync(path.join(os.tmpdir(), 'acts-v2global-'));
  fs.writeFileSync(path.join(globalDir, 'acts'), `#!/usr/bin/env bash
if [ "$1" = "version" ]; then echo "acts 2.99.0"; exit 0; fi
echo "V2_CALLED:$@"
`);
  fs.chmodSync(path.join(globalDir, 'acts'), 0o755);

  const prevPath = process.env.PATH;
  process.env.PATH = `${globalDir}:${prevPath}`;
  try {
    const hooks2 = await ActsPlugin({ directory: v1dir });
    const tools2 = await hooks2.tools();
    const res2 = await tools2.acts.handler({ command: 'stack status' });
    assert.ok(res2.content[0].text.includes('V2_CALLED'), 'v2 global binary preferred over stale v1 local');
    ok('v1 local binary skipped when v2 global exists (version-aware discovery)');
  } finally {
    process.env.PATH = prevPath;
    fs.rmSync(v1dir, { recursive: true, force: true });
    fs.rmSync(globalDir, { recursive: true, force: true });
  }

  console.log(`\n${passed} checks passed.`);
  cleanup();
} catch (e) {
  cleanup();
  console.error('\nTEST FAILED:', e.message);
  process.exit(1);
}
