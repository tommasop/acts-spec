import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFileSync, execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─────────────────────────────────────────────
// Codebase Memory Plugin v1.0.0
//
// Wraps codebase-memory-mcp (https://github.com/DeusData/codebase-memory-mcp)
// as a native OpenCode plugin. Auto-installs the binary on first use and
// exposes its code-intelligence tools directly (no separate MCP server).
// Works hand-in-hand with the OpenCode `references` config for cross-repo
// orchestration alongside the ACTS plugin.
// ─────────────────────────────────────────────

const PLUGIN_VERSION = '1.0.0';
const CBM_INSTALL_URL = 'https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh';

// codebase-memory-mcp tools exposed as native OpenCode tools.
// Each takes a single `args` JSON string (the tool's CLI payload).
const CBM_TOOLS = [
  { name: 'index_repository', desc: 'Index a repository into the knowledge graph (auto-sync keeps it fresh)', arg: '{"repo_path":"/abs/path"}' },
  { name: 'list_projects', desc: 'List all indexed projects with node/edge counts', arg: '{}' },
  { name: 'delete_project', desc: 'Remove a project and all of its graph data', arg: '{"project":"name"}' },
  { name: 'index_status', desc: 'Check indexing status of a project', arg: '{"project":"name"}' },
  { name: 'search_graph', desc: 'Structured search by label, name pattern, file pattern, degree filters', arg: '{"name_pattern":".*Handler.*","label":"Function"}' },
  { name: 'trace_path', desc: 'BFS call-path tracing (inbound/outbound) across repos', arg: '{"function_name":"Search","direction":"both"}' },
  { name: 'detect_changes', desc: 'Map git diff to affected symbols + blast radius with risk classification', arg: '{"repo_path":"/abs/path"}' },
  { name: 'query_graph', desc: 'Read-only Cypher-like graph query across the fleet', arg: '{"query":"MATCH (f:Function) RETURN f.name LIMIT 5"}' },
  { name: 'get_graph_schema', desc: 'Node/edge counts, relationship patterns, property definitions', arg: '{}' },
  { name: 'get_code_snippet', desc: 'Read source code for a function by qualified name', arg: '{"qualified_name":"proj.path.fn"}' },
  { name: 'get_architecture', desc: 'Codebase overview: languages, packages, routes, hotspots, clusters', arg: '{}' },
  { name: 'search_code', desc: 'Grep-like text search within indexed project files', arg: '{"pattern":"foo"}' },
  { name: 'manage_adr', desc: 'CRUD for Architecture Decision Records', arg: '{"action":"create","title":"..."}' },
  { name: 'ingest_traces', desc: 'Ingest runtime traces to validate HTTP_CALLS edges', arg: '{"trace_file":"/path"}' },
];

export const CbmPlugin = async ({ client, directory }) => {
  // ─── Binary Discovery ───────────────────────
  const findCbmBinary = () => {
    const localPath = path.join(directory, '.acts', 'bin', 'codebase-memory-mcp');
    if (fs.existsSync(localPath)) return localPath;
    try {
      const which = execSync('which codebase-memory-mcp', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      return which.trim();
    } catch {
      return null;
    }
  };

  const cbmCacheDir = path.join(directory, '.acts', 'cbm');

  // ─── Auto-install ───────────────────────────
  // Downloads the CBM binary into .acts/bin on first use. Best-effort and
  // non-fatal: if it fails (offline, no curl) the tools still register and
  // report a clear install hint.
  const ensureCbm = () => {
    const existing = findCbmBinary();
    if (existing) return { ok: true, path: existing };
    try {
      const binDir = path.join(directory, '.acts', 'bin');
      fs.mkdirSync(binDir, { recursive: true });
      execSync(
        `bash -c "curl -fsSL ${CBM_INSTALL_URL} | bash -s -- --dir '${binDir}' --skip-config"`,
        { encoding: 'utf8', stdio: 'ignore', timeout: 180000, cwd: directory }
      );
      const installed = path.join(binDir, 'codebase-memory-mcp');
      if (fs.existsSync(installed)) return { ok: true, path: installed };
    } catch { /* fall through */ }
    return { ok: false, path: null };
  };

  let cbmBinary = findCbmBinary();

  // ─── OpenCode references (the cross-repo fleet) ──
  const loadReferences = () => {
    try {
      const cfgPath = path.join(directory, 'opencode.json');
      if (!fs.existsSync(cfgPath)) return {};
      const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
      return cfg.references || {};
    } catch {
      return {};
    }
  };

  const references = loadReferences();

  const resolveRefPath = (alias) => {
    const ref = references[alias];
    if (!ref || !ref.path) return null;
    return path.resolve(directory, ref.path);
  };

  // Longest-prefix match of an absolute file path to a reference alias.
  const repoForFile = (absFile) => {
    let best = null;
    for (const alias of Object.keys(references)) {
      const rp = resolveRefPath(alias);
      if (rp && absFile.startsWith(rp + path.sep)) {
        if (!best || rp.length > best.length) best = alias;
      }
    }
    return best;
  };

  // ─── Safe CBM Runner ────────────────────────
  const runCbm = (cliArgs, opts = {}) => {
    let bin = cbmBinary;
    if (!bin) {
      const r = ensureCbm();
      if (r.ok) { bin = r.path; cbmBinary = r.path; }
    }
    if (!bin) {
      throw new Error(
        'codebase-memory-mcp not available. Run `cbm_install` or install manually:\n' +
        `curl -fsSL ${CBM_INSTALL_URL} | bash`
      );
    }
    const safeArgs = ['cli', ...cliArgs.map(a => String(a))];
    return execFileSync(bin, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: opts.timeout || 120000,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, CBM_CACHE_DIR: cbmCacheDir },
      ...opts
    });
  };

  // ─── ACTS binary (for the scope bridge) ─────
  const findActsBinary = () => {
    const localPath = path.join(directory, '.acts', 'bin', 'acts');
    if (fs.existsSync(localPath)) return localPath;
    try {
      const which = execSync('which acts', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      return which.trim();
    } catch {
      return null;
    }
  };

  const actsBinary = findActsBinary();

  const runActs = (args, options = {}) => {
    if (!actsBinary) throw new Error('ACTS binary not found.');
    const safeArgs = args.map(a => String(a));
    return execFileSync(actsBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: options.timeout || 30000,
      stdio: ['pipe', 'pipe', 'pipe'],
      ...options
    });
  };

  // ─── System Context Builder ─────────────────
  const buildSystemContext = () => {
    if (!cbmBinary && !ensureCbm().ok) {
      // No binary and can't install — skip context (tools still hint install).
    }
    if (Object.keys(references).length === 0) return [];

    const lines = [];
    lines.push(`# Cross-Repo Memory (codebase-memory-mcp plugin)`);
    lines.push(`- Fleet repos (OpenCode references): ${Object.keys(references).join(', ')}`);
    lines.push(`- Native tools available: index_repository, search_graph, trace_path, query_graph, get_architecture, detect_changes, …`);
    lines.push(`- Fleet helpers: cbm_repos, cbm_index_all, cbm_changes, cbm_install`);
    lines.push(`- ACTS bridge: acts_memory scope <task_id> maps a task's files to its repos`);

    // Per active-task repo span (read ACTS state if present)
    if (actsBinary) {
      try {
        const state = JSON.parse(runActs(['state', 'read']));
        const inProgress = (state.tasks || []).filter(t => t.status === 'IN_PROGRESS');
        const spanned = [];
        for (const task of inProgress) {
          const files = task.files_touched || [];
          const repos = new Set();
          for (const f of files) {
            const r = repoForFile(path.resolve(directory, f));
            if (r) repos.add(r);
          }
          if (repos.size) spanned.push(`  - ${task.id} spans: ${[...repos].join(', ')}`);
        }
        if (spanned.length) lines.push(...spanned);
      } catch { /* ignore — ACTS state not required for code intelligence */ }
    }

    return [lines.join('\n')];
  };

  // ─── Tools ──────────────────────────────────
  const nativeTools = {};
  for (const t of CBM_TOOLS) {
    nativeTools[t.name] = {
      description: `[codebase-memory-mcp] ${t.desc}`,
      inputSchema: {
        type: 'object',
        properties: {
          args: {
            type: 'string',
            description: `JSON args for ${t.name}, e.g. ${t.arg}`
          }
        },
        required: ['args']
      },
      handler: async ({ args }) => {
        try {
          const out = runCbm([t.name, args]);
          return { content: [{ type: 'text', text: out }] };
        } catch (error) {
          return {
            content: [{ type: 'text', text: `cbm ${t.name} error: ${error.stderr || error.message}` }],
            isError: true
          };
        }
      }
    };
  }

  const fleetTools = {
    // Force (re)install the CBM binary into .acts/bin
    cbm_install: {
      description: 'Download/install the codebase-memory-mcp binary into .acts/bin (auto-run on first use).',
      inputSchema: { type: 'object', properties: {} },
      handler: async () => {
        const r = ensureCbm();
        if (r.ok) {
          return { content: [{ type: 'text', text: `codebase-memory-mcp installed at: ${r.path}` }] };
        }
        return {
          content: [{
            type: 'text',
            text: `Install failed. Install manually:\ncurl -fsSL ${CBM_INSTALL_URL} | bash`
          }],
          isError: true
        };
      }
    },

    // List configured references
    cbm_repos: {
      description: 'List the OpenCode `references` repos that make up the cross-repo fleet.',
      inputSchema: { type: 'object', properties: {} },
      handler: async () => {
        const aliases = Object.keys(references);
        if (aliases.length === 0) {
          return { content: [{ type: 'text', text:
            'No `references` configured in opencode.json.\n' +
            'Add a `references` block to enable cross-repo indexing, e.g.:\n' +
            '  "references": { "ui-payments": { "path": "../ui-payments" } }' }] };
        }
        const lines = ['# Configured Repositories (OpenCode references)'];
        for (const a of aliases) {
          const ref = references[a];
          const rp = resolveRefPath(a);
          lines.push(`- ${a}: ${ref.path || ref.repository}${ref.description ? ' — ' + ref.description : ''}`);
          if (rp) lines.push(`  resolved: ${rp}`);
        }
        lines.push(`\nKnowledge graph store: ${cbmCacheDir}`);
        lines.push('Index with: cbm_index_all');
        return { content: [{ type: 'text', text: lines.join('\n') }] };
      }
    },

    // Index all referenced repos into the shared store
    cbm_index_all: {
      description: 'Index every local OpenCode reference repo into the shared knowledge graph.',
      inputSchema: { type: 'object', properties: {} },
      handler: async () => {
        const aliases = Object.keys(references);
        if (aliases.length === 0) return { content: [{ type: 'text', text: 'No `references` configured in opencode.json.' }] };
        const results = [];
        for (const a of aliases) {
          const rp = resolveRefPath(a);
          if (!rp) { results.push(`⚠️ ${a}: git repository reference (not indexed locally)`); continue; }
          try {
            const out = runCbm(['index_repository', JSON.stringify({ repo_path: rp })]);
            results.push(`✅ ${a} (${rp})\n${out}`);
          } catch (e) {
            results.push(`❌ ${a}: ${e.stderr || e.message}`);
          }
        }
        return { content: [{ type: 'text', text: results.join('\n\n') }] };
      }
    },

    // Detect changes across the fleet
    cbm_changes: {
      description: 'Map uncommitted diffs to affected symbols + repos (blast radius) across all referenced repos.',
      inputSchema: { type: 'object', properties: {} },
      handler: async () => {
        const aliases = Object.keys(references);
        if (aliases.length === 0) return { content: [{ type: 'text', text: 'No `references` configured in opencode.json.' }] };
        const results = [];
        for (const a of aliases) {
          const rp = resolveRefPath(a);
          if (!rp) continue;
          try {
            const out = runCbm(['detect_changes', JSON.stringify({ repo_path: rp })]);
            results.push(`## ${a}\n${out}`);
          } catch (e) {
            results.push(`## ${a}\n${e.stderr || e.message}`);
          }
        }
        return { content: [{ type: 'text', text: results.join('\n\n') }] };
      }
    },

    // ACTS bridge: map a task's files to repos
    'acts_memory': {
      description: 'ACTS ↔ codebase-memory-mcp bridge. Subcommand: scope <task_id> maps an ACTS task\'s files_touched to the repos it spans.',
      inputSchema: {
        type: 'object',
        properties: {
          command: { type: 'string', description: 'e.g. "scope T3"' }
        },
        required: ['command']
      },
      handler: async ({ command }) => {
        const args = (command || '').trim().split(/\s+/).filter(Boolean);
        const sub = args[0];
        const err = (m) => ({ content: [{ type: 'text', text: m }], isError: true });
        try {
          if (sub === 'scope') {
            const taskId = args[1];
            if (!taskId) return err('Usage: acts_memory scope <task_id>');
            if (!actsBinary) return err('ACTS binary not found; cannot read task files.');
            const task = JSON.parse(runActs(['task', 'get', taskId]));
            const files = task.files_touched || [];
            const mapping = files.map(f => ({ file: f, repo: repoForFile(path.resolve(directory, f)) || 'unknown' }));
            const repos = [...new Set(mapping.map(m => m.repo))];
            let text = `# Task ${taskId} — cross-repo span\n`;
            text += `Repos touched: ${repos.join(', ') || 'none'}\n\n`;
            if (mapping.length) {
              for (const m of mapping) text += `- ${m.file} → ${m.repo}\n`;
            } else {
              text += 'No files_touched recorded for this task yet.\n';
            }
            return { content: [{ type: 'text', text }] };
          }
          return err('Unknown subcommand. Available: scope <task_id>');
        } catch (error) {
          return { content: [{ type: 'text', text: `acts_memory error: ${error.stderr || error.message}` }], isError: true };
        }
      }
    }
  };

  // ─── Hooks ─────────────────────────────────
  return {
    'experimental.chat.system.transform': async (_input, output) => {
      const context = buildSystemContext();
      if (context.length > 0) {
        output.system = [...output.system, ...context];
      }
    },

    tools: async () => ({ ...nativeTools, ...fleetTools }),

    config: async () => {
      const r = ensureCbm();
      console.log(`[CBM] plugin v${PLUGIN_VERSION} loaded. Binary: ${r.ok ? r.path : 'not installed (run cbm_install)'}`);
      if (Object.keys(references).length > 0) {
        console.log(`[CBM] Fleet references: ${Object.keys(references).join(', ')}`);
      }
    }
  };
};
