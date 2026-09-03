// Offline test for the ponytail-rules.js runtime plugin: per-run AGENTS.md
// project-rules directive + magic usage-rules (core subset) injection.
// Uses temp project roots so resolution, gating, idempotence, and toggles are
// exercised without touching the real filesystem config.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import assert from 'assert';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, '..', '.opencode', 'plugins', 'ponytail-rules.js');

let passed = 0;
const ok = (name) => { passed++; console.log(`  ✓ ${name}`); };

// Isolate the plugin from the machine's ~/.config/ponytail/config.json.
const isolatedCfg = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-cfg-'));
const prevXdg = process.env.XDG_CONFIG_HOME;
process.env.XDG_CONFIG_HOME = isolatedCfg;

const writeRules = (dir, files = ['coding-practices.md', 'error-handling.md']) => {
  fs.mkdirSync(dir, { recursive: true });
  for (const f of files) fs.writeFileSync(path.join(dir, f), `# rule ${f}\n`);
};

const runTransform = async (root) => {
  const { PonytailRules } = await import(pluginPath);
  const plugin = await PonytailRules({ directory: root, worktree: root });
  const output = { system: [] };
  await plugin['experimental.chat.system.transform']({}, output);
  return output.system;
};

// ── 1. Consumer project: deps/magic/usage-rules ─────────────────────────
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-consumer-'));
  fs.writeFileSync(path.join(root, 'AGENTS.md'), '# consumer\n');
  writeRules(path.join(root, 'deps', 'magic', 'usage-rules'));

  const system = await runTransform(root);
  const magic = system.find((s) => s.includes('PONYTAIL_MAGIC_RULES'));
  assert(magic, 'magic block injected for deps/magic consumer');
  assert(magic.includes('# rule coding-practices.md'), 'coding-practices content present');
  assert(magic.includes('# rule error-handling.md'), 'error-handling content present');
  assert(system.some((s) => s.includes('PONYTAIL_PROJECT_RULES')), 'project directive present');
  ok('consumer (deps/magic/usage-rules) injects magic core subset + project directive');
}

// ── 2. Magic source repo: usage-rules at root ───────────────────────────
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-magic-src-'));
  writeRules(path.join(root, 'usage-rules'));
  const system = await runTransform(root);
  assert(system.some((s) => s.includes('# rule coding-practices.md')), 'source repo injection works');
  ok('magic source repo (usage-rules/) injection works');
}

// ── 3. Reference fallback: opencode.json references.magic.path ──────────
{
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-ref-'));
  const root = path.join(parent, 'project');
  fs.mkdirSync(root, { recursive: true });
  writeRules(path.join(parent, 'magic-lib', 'usage-rules'));
  fs.writeFileSync(path.join(root, 'opencode.json'), JSON.stringify({
    references: { magic: { path: '../magic-lib' } },
  }));
  const system = await runTransform(root);
  assert(system.some((s) => s.includes('# rule coding-practices.md')), 'reference fallback works');
  ok('references.magic.path fallback works');
}

// ── 4. Gating: no magic source → no magic block ─────────────────────────
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-plain-'));
  fs.writeFileSync(path.join(root, 'AGENTS.md'), '# plain\n');
  const system = await runTransform(root);
  assert(!system.some((s) => s.includes('Magic Usage Rules')), 'no magic block for non-magic project');
  assert(system.some((s) => s.includes('PONYTAIL_PROJECT_RULES')), 'project directive still present');
  ok('non-magic project gated (no magic block, directive present)');
}

// ── 5. Idempotence: markers prevent duplication on later turns ──────────
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-idem-'));
  writeRules(path.join(root, 'deps', 'magic', 'usage-rules'));
  const { PonytailRules } = await import(pluginPath);
  const plugin = await PonytailRules({ directory: root, worktree: root });
  const output = { system: [] };
  await plugin['experimental.chat.system.transform']({}, output);
  const first = output.system.length;
  await plugin['experimental.chat.system.transform']({}, output);
  assert.strictEqual(output.system.length, first, 'second turn adds nothing');
  ok('idempotent across turns');
}

// ── 6. Toggle: PONYTAIL_MAGIC_RULES=off → no magic block ────────────────
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-toggle-'));
  writeRules(path.join(root, 'deps', 'magic', 'usage-rules'));
  process.env.PONYTAIL_MAGIC_RULES = 'off';
  try {
    const system = await runTransform(root);
    assert(!system.some((s) => s.includes('Magic Usage Rules')), 'magic block suppressed');
    assert(system.some((s) => s.includes('PONYTAIL_PROJECT_RULES')), 'directive unaffected');
    ok('PONYTAIL_MAGIC_RULES=off suppresses magic block only');
  } finally {
    delete process.env.PONYTAIL_MAGIC_RULES;
  }
}

if (prevXdg === undefined) delete process.env.XDG_CONFIG_HOME;
else process.env.XDG_CONFIG_HOME = prevXdg;

console.log(`\nponytail-rules: ${passed} checks passed`);