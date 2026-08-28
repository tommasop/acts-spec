import path from 'path';
import os from 'os';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFileSync, execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─────────────────────────────────────────────
// ACTS v2 OpenCode Plugin (Git-native)
// ─────────────────────────────────────────────

const PLUGIN_VERSION = '2.0.0';

export const ActsPlugin = async ({ directory }) => {
  // ─── Binary Discovery ───────────────────────
  // Candidate order: project-local .acts/bin first (self-contained/CI), then
  // the global binary on PATH. We then prefer a v2 binary over a stale v1
  // binary that may be shadowing it (v1 auto-creates a SQLite db and errors on
  // v2 commands). If neither reports v2, fall back to the first found.
  const findActsBinary = () => {
    const candidates = [];
    const localPath = path.join(directory, '.acts', 'bin', 'acts');
    if (fs.existsSync(localPath)) candidates.push(localPath);
    try {
      const which = execSync('which acts', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      const p = which.trim();
      if (p && fs.existsSync(p)) candidates.push(p);
    } catch { /* no global */ }

    const isV2 = (p) => {
      try {
        const out = execFileSync(p, ['version'], { encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'ignore'] });
        return /2\.\d+\.\d+/.test(out);
      } catch {
        return false;
      }
    };

    for (const c of candidates) if (isV2(c)) return c;
    return candidates[0] || null;
  };

  const actsBinary = findActsBinary();

  // ─── Archify Renderer Discovery ────────────
  // Locate archify/bin/archify.mjs (the tt-a1i/archify skill) in the standard
  // skill install locations, mirroring the Zig binary's discovery.
  const findArchifyRenderer = (cwd) => {
    const candidates = [
      path.join(cwd, '.opencode', 'skills', 'archify', 'bin', 'archify.mjs'),
      path.join(cwd, '.agents', 'skills', 'archify', 'bin', 'archify.mjs'),
      path.join(cwd, 'archify', 'bin', 'archify.mjs'),
      path.join(os.homedir(), '.config', 'opencode', 'skills', 'archify', 'bin', 'archify.mjs'),
      path.join(os.homedir(), '.agents', 'skills', 'archify', 'bin', 'archify.mjs'),
      path.join(os.homedir(), '.claude', 'skills', 'archify', 'bin', 'archify.mjs'),
    ];
    for (const c of candidates) if (fs.existsSync(c)) return c;
    return null;
  };

  // ─── Safe Command Runner ────────────────────
  const runActs = (args, options = {}) => {
    if (!actsBinary) {
      throw new Error('ACTS v2 binary not found. Install it or run `acts stack create <id>` to start.');
    }
    const safeArgs = args.map(a => String(a));
    return execFileSync(actsBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: options.timeout || 120000,
      stdio: ['pipe', 'pipe', 'pipe'],
      ...options
    });
  };

  // ─── Project Detection (git-native) ─────────
  const isActsProject = () => {
    return fs.existsSync(path.join(directory, '.acts', 'stack.json'));
  };

  const actsProject = isActsProject();

  // ─── Plugin State ───────────────────────────
  const pluginStatePath = path.join(directory, '.acts', 'plugin-state.json');
  const loadPluginState = () => {
    try {
      if (fs.existsSync(pluginStatePath)) {
        return JSON.parse(fs.readFileSync(pluginStatePath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { mode: 'on', version: PLUGIN_VERSION };
  };
  const savePluginState = (state) => {
    try {
      fs.writeFileSync(pluginStatePath, JSON.stringify(state, null, 2));
    } catch (e) {
      console.warn('[ACTS] Failed to save plugin state:', e.message);
    }
  };
  const pluginState = loadPluginState();

  // ─── Manifest reader ────────────────────────
  const readStackManifest = () => {
    try {
      if (fs.existsSync(path.join(directory, '.acts', 'stack.json'))) {
        return JSON.parse(fs.readFileSync(path.join(directory, '.acts', 'stack.json'), 'utf8'));
      }
    } catch { /* ignore */ }
    return null;
  };

  // ─── Cached stack status ────────────────────
  let cachedStatus = null;
  let cachedStatusTime = 0;
  const STATUS_CACHE_TTL = 60000;

  const refreshStackStatus = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const now = Date.now();
      if (cachedStatus && (now - cachedStatusTime) < STATUS_CACHE_TTL) {
        return cachedStatus;
      }
      const raw = runActs(['stack', 'status', '--json']);
      cachedStatus = JSON.parse(raw);
      cachedStatusTime = now;
      return cachedStatus;
    } catch {
      return null;
    }
  };

  if (pluginState.mode !== 'off') {
    refreshStackStatus();
  }

  // ─── Active change resolution ───────────────
  // The active change on the feature branch is the last non-MERGED change.
  const resolveActiveChange = () => {
    const status = refreshStackStatus();
    if (!status || !Array.isArray(status.changes)) return null;
    let branch = null;
    try {
      branch = execSync('git rev-parse --abbrev-ref HEAD', { encoding: 'utf8', cwd: directory, stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    } catch { /* not a git repo or no HEAD */ }
    if (!branch) {
      // Fall back to the last non-terminal change.
      return [...status.changes].reverse().find(c => !['MERGED', 'APPROVED'].includes(c.status || ''))?.id || null;
    }
    if (branch === status.branch) {
      // On the feature branch → top (last) non-merged change.
      const open = status.changes.filter(c => (c.status || '') !== 'MERGED');
      return open.length ? open[open.length - 1].id : null;
    }
    const match = status.changes.find(c => c.branch === branch);
    return match ? match.id : null;
  };

  // Auto-inject the active change's scoped context pack into the system prompt
  // so the agent starts with acceptance criteria + verification + notes, bounded
  // to the change (not the whole repo). Falls back gracefully when binary missing.
  const buildActiveChangeContext = () => {
    if (!actsBinary) return [];
    const id = resolveActiveChange();
    if (!id) return [];
    try {
      const raw = execFileSync(actsBinary, ['context', id], {
        encoding: 'utf8', cwd: directory, timeout: 30000, stdio: ['pipe', 'pipe', 'ignore']
      });
      return [`# ACTS Active Change: ${id}\n${raw}`];
    } catch {
      return [];
    }
  };

  // ─── CBM blast radius (best-effort, self-contained) ──
  // Reads the change's files from .acts/stack.json + git diff, then — if a CBM
  // binary is discoverable — traces cross-repo callers/callees per file and
  // stores the edge counts on the change (risk_cbm) for `acts risk`.
  const findCbmBin = () => {
    const home = process.env.HOME || '~';
    const name = process.platform === 'win32' ? 'codebase-memory-mcp.exe' : 'codebase-memory-mcp';
    const candidates = [
      path.join(home, '.cache', 'codebase-memory-mcp', 'bin', name),
      path.join(home, '.local', 'bin', name),
      path.join(directory, '.acts', 'bin', name),
    ];
    for (const c of candidates) if (fs.existsSync(c)) return c;
    try {
      const p = execSync('which codebase-memory-mcp', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
      if (p && fs.existsSync(p)) return p;
    } catch { /* none */ }
    return null;
  };

  const computeBlastRadius = async (changeId) => {
    const manifest = readStackManifest();
    if (!manifest) return null;
    const change = (manifest.changes || []).find(c => c.id === changeId);
    if (!change) return null;
    let files = [];
    try {
      const from = change.start_sha || manifest.base_branch || '';
      const to = change.end_sha || 'HEAD';
      files = execFileSync('git', ['diff', '--name-only', from, to], {
        encoding: 'utf8', cwd: directory, stdio: ['pipe', 'pipe', 'pipe']
      }).split('\n').map(s => s.trim()).filter(Boolean);
    } catch { /* fall through */ }
    if (files.length === 0) return null;

    const cbmBin = findCbmBin();
    const out = ['## CBM Blast Radius', `Files: ${files.length}`];
    let crossEdges = 0;

    if (!cbmBin) {
      out.push('(CBM binary not installed — run `acts setup --with-cbm` for cross-repo trace data; git-level risk computed locally.)');
      return out.join('\n');
    }

    const cacheDir = path.join(process.env.HOME || '~', '.cache', 'codebase-memory-mcp');
    try {
      const projectsRaw = execFileSync(cbmBin, ['cli', 'list_projects', '{}'], {
        encoding: 'utf8', cwd: directory, timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, CBM_CACHE_DIR: cacheDir }
      });
      const projects = (JSON.parse(projectsRaw).projects || []).map(p => p.name);
      for (const f of files.slice(0, 20)) {
        // Find a project by matching the file's top-level dir to a reference alias is
        // complex; trace within each project is not file-scoped, so keep it simple:
        // for each project, search functions in this file, then trace each.
        for (const proj of projects) {
          try {
            const searchRaw = execFileSync(cbmBin, ['cli', 'search_graph', JSON.stringify({ project: proj, file_path: f, label: 'Function', limit: 5 })], {
              encoding: 'utf8', cwd: directory, timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'],
              env: { ...process.env, CBM_CACHE_DIR: cacheDir }
            });
            const syms = JSON.parse(searchRaw).results || [];
            for (const sym of syms.slice(0, 3)) {
              try {
                const traceRaw = execFileSync(cbmBin, ['cli', 'trace_path', JSON.stringify({ project: proj, function_name: sym.name, direction: 'both', depth: 2, mode: 'cross_service' })], {
                  encoding: 'utf8', cwd: directory, timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'],
                  env: { ...process.env, CBM_CACHE_DIR: cacheDir }
                });
                const trace = JSON.parse(traceRaw);
                const callers = (trace.callers || []).length;
                const callees = (trace.callees || []).length;
                const cross = (trace.cross_repo_callers || trace.cross_repo_edges || 0);
                crossEdges += typeof cross === 'number' ? cross : 0;
                if (callers + callees > 0) {
                  out.push(`- ${f}: ${sym.name} (callers: ${callers}, callees: ${callees})`);
                }
              } catch { /* skip trace */ }
            }
          } catch { /* skip search */ }
        }
      }
      // Persist the edge count so `acts risk` reflects it.
      if (crossEdges > 0) {
        try {
          const metaPath = path.join(directory, '.acts', 'stack.json');
          const manifest2 = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
          const ch = (manifest2.changes || []).find(c => c.id === changeId);
          if (ch) {
            ch.risk_cbm = { cross_repo_edges: crossEdges, high_complexity_symbols: 0 };
            fs.writeFileSync(metaPath, JSON.stringify(manifest2, null, 2) + '\n');
          }
        } catch { /* ignore */ }
      }
    } catch {
      out.push('(CBM trace failed — git-level risk computed locally.)');
    }

    out.push(`Cross-repo edges detected: ${crossEdges}`);
    return out.join('\n');
  };

  // ─── Context Builders ───────────────────────
  const getBootstrapContent = () => {
    return `<EXTREMELY_IMPORTANT>
This project uses ACTS v2 (Agent Collaborative Tracking Standard) — a git-native coordination protocol.

### Rules
- Agent MUST read state before writing code: \`acts stack status\`
- Agent MUST load durable context before starting work on a change: \`acts context <change>\`
- Agent MUST NOT submit a change for review until \`acts verify <change>\` passes.
- Agent MUST record a session note (\`acts note <change> -m "..."\`) and checkpoint (\`acts checkpoint <change> -s "..."\`) before ending a session.
- Agent MUST stay within the change's scope; use \`acts scope <change> <file>\` to check ownership.
- Agent MUST get developer approval on the PR before \`acts approve\` / \`acts stack land\`.
- Agent MUST run \`acts validate\` before finishing.

ACTS v2 Commands:
- acts stack create <id> [-t <title>]      Start a new stack (base branch + manifest)
- acts stack status [--json]               Show stack tree + change statuses
- acts stack land                          Merge APPROVED changes bottom-up
- acts change add <id> -t <title> [--accept <criteria>]  Add a change on top of the stack
- acts change status [<id>]                Show change details
- acts verify [<id>] [--all]               Run quality gates; record evidence (GATE for review)
- acts review <id>                         Submit stacked PR (requires verify to pass)
- acts approve <id>                        Mark approved after human PR review
- acts rework <id>                         Reopen for rework (clears approval)
- acts context [<id>]                      Emit scoped context pack (durable task state)
- acts note <id> -m <text>                 Append a session note
- acts checkpoint <id> -s <summary>        Record a status checkpoint
- acts redirect <id> --accept <criteria>   Update scope mid-flight without context loss
- acts scope <id> <file>                   Check file ownership (derived from diffs)
- acts validate                            Validate manifest + branch consistency

Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED

Workflow: plan (spec-kit/superpowers) -> stack create -> change add -> context -> implement ->
verify -> review (PR) -> approve -> stack land -> note + checkpoint + validate.
</EXTREMELY_IMPORTANT>`;
  };

  const buildSystemContext = () => {
    const status = refreshStackStatus();
    if (!status) return [];

    const lines = [];
    lines.push(`# ACTS v2 Stack Context`);
    lines.push(`- Stack: ${status.id} — ${status.title}`);
    lines.push(`- Feature branch: ${status.branch} (off ${status.base_branch})`);
    lines.push(`- ACTS Mode: ${pluginState.mode}`);

    if (Array.isArray(status.changes) && status.changes.length > 0) {
      lines.push(`## Changes`);
      for (const c of status.changes) {
        const st = c.status || 'TODO';
        const range = c.start_sha ? `${(c.start_sha || '').slice(0, 7)}..${(c.end_sha || '…').slice(0, 7)}` : '';
        lines.push(`- ${c.id}: ${c.title} [${st}] ${range}`);
      }
    }

    // Cross-repo fleet (from opencode.json references; CBM tools come natively
    // via the codebase-memory-mcp MCP server — no plugin needed).
    const fleet = loadFleetReferences();
    if (fleet.length > 0) {
      lines.push(`## Cross-Repo Fleet`);
      lines.push(`- Repos: ${fleet.map(r => r.alias).join(', ')}`);
      lines.push(`- Graph tools: search_graph, trace_path, query_graph, get_architecture (via MCP)`);
      lines.push(`- Fleet commands: acts graph repos | index --all | bootstrap | span <id>`);
      lines.push(`- Risk: acts tech-lead <id>  |  acts doc-risk <file>`);
    }

    return [lines.join('\n')];
  };

  // Fleet references from opencode.json (for the system-context block).
  const loadFleetReferences = () => {
    try {
      const cfgPath = path.join(directory, 'opencode.json');
      if (!fs.existsSync(cfgPath)) return [];
      const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
      const refs = cfg.references || {};
      return Object.keys(refs).map(alias => ({ alias, ...refs[alias] }));
    } catch {
      return [];
    }
  };

  // ─── Hooks ──────────────────────────────────
  return {
    'experimental.chat.system.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      const context = buildSystemContext();
      const active = buildActiveChangeContext();
      if (context.length > 0 || active.length > 0) {
        output.system = [...output.system, ...context, ...active];
      }
    },

    'experimental.chat.messages.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      if (!output.messages.length) return;

      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      const alreadyInjected = firstUser.parts.some(
        p => p.type === 'text' && p.text.includes('ACTS v2 (Agent Collaborative Tracking Standard)')
      );
      if (alreadyInjected) return;

      const bootstrap = getBootstrapContent();
      firstUser.parts.unshift({ type: 'text', text: bootstrap });
    },

    tools: async () => {
      if (!actsBinary) {
        return {
          acts_install: {
            description: 'Install ACTS v2 in this project (binary not found)',
            inputSchema: {
              type: 'object',
              properties: {
                stack_id: { type: 'string', description: 'Stack ID to create after install' }
              }
            },
            handler: async ({ stack_id }) => {
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS v2 binary not found. Build/install with:\n' +
                        '  cd acts-core && zig build release\n' +
                        '  sudo cp zig-out/bin/acts /usr/local/bin/acts\n' +
                        'Then start a stack: acts stack create ' + (stack_id || '<id>') + ' -t "<title>"'
                }]
              };
            }
          }
        };
      }

      return {
        // ─── Main ACTS Tool ─────────────────────
        acts: {
          description: 'Execute ACTS v2 (git-native coordination protocol) commands. ' +
            'Common: stack status, context <change>, change add <id> -t <title>, ' +
            'verify <change>, review <change>, approve <change>, note <change> -m <text>, ' +
            'checkpoint <change> -s <summary>, redirect <change> --accept <criteria>, ' +
            'scope <change> <file>, validate',
          inputSchema: {
            type: 'object',
            properties: {
              command: {
                type: 'string',
                description: 'ACTS v2 command to execute (e.g., "context c1", "verify c1", "stack status")'
              }
            },
            required: ['command']
          },
          handler: async ({ command }) => {
            try {
              const args = command.trim().split(/\s+/);
              const result = runActs(args);
              cachedStatus = null; // invalidate cache after mutations
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}` }],
                isError: true
              };
            }
          }
        },

        // ─── Context Pack Tool ──────────────────
        acts_context: {
          description: 'Load the ACTS v2 scoped context pack for a change (or the current branch\'s change). ' +
            'ALWAYS call this before writing code on a change. Surfaces acceptance criteria, parent chain, ' +
            'verification status, checkpoint, session notes, and changed files. With blast_radius=true, ' +
            'also appends CBM cross-repo callers/callees for each changed file.',
          inputSchema: {
            type: 'object',
            properties: {
              change_id: {
                type: 'string',
                description: 'Change ID (e.g., c1). Omit to auto-resolve from the current git branch.'
              },
              blast_radius: {
                type: 'boolean',
                description: 'Append CBM cross-repo blast radius for the change\'s files (default: true)'
              }
            }
          },
          handler: async ({ change_id, blast_radius = true }) => {
            try {
              const id = change_id || resolveActiveChange() || '';
              const args = id ? ['context', id] : ['context'];
              const result = runActs(args);
              let text = result;
              if (blast_radius && id) {
                const br = await computeBlastRadius(id);
                if (br) text += '\n' + br;
              }
              return { content: [{ type: 'text', text }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}\n\nRun \`acts stack status\` to see active changes.` }],
                isError: true
              };
            }
          }
        },

        // ─── Zeplin Contract Tool ───────────────
        acts_zeplin: {
          description: 'Extract an API contract from a Zeplin flow or scenario link (via acts-zeplin-contract.mjs) ' +
            'for analysis and planning. Use when a design link is given. Detects flow vs scenario URLs.',
          inputSchema: {
            type: 'object',
            properties: {
              url: { type: 'string', description: 'Zeplin link (flow board, scenario, or zpl.io shortlink)' },
              notes: { type: 'boolean', description: 'Include screen notes/annotations (slower)' }
            },
            required: ['url']
          },
          handler: async ({ url, notes = false }) => {
            const script = path.join(__dirname, '..', 'acts-zeplin-contract.mjs');
            if (!fs.existsSync(script)) {
              return {
                content: [{ type: 'text', text: 'acts-zeplin-contract.mjs not found in project root.' }],
                isError: true
              };
            }
            const kind = /\/flow\//i.test(url) ? 'flow' : 'scenario';
            const args = [script, '--' + kind, url, ...(notes ? ['--notes'] : [])];
            try {
              const result = execFileSync('node', args, {
                encoding: 'utf8',
                cwd: directory,
                timeout: 120000,
                stdio: ['pipe', 'pipe', 'pipe']
              });
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `acts_zeplin error: ${error.stderr || error.message}\n\nSet ZEPLIN_ACCESS_TOKEN or configure the zeplin MCP server in opencode.json.` }],
                isError: true
              };
            }
          }
        },

        // ─── Archify Diagram Tool ─────────────
        acts_archify: {
          description: 'Validate or render an archify diagram (architecture/workflow/sequence/dataflow/lifecycle) ' +
            'from typed JSON IR (tt-a1i/archify). Install the renderer with `acts archify install`. ' +
            'Use after building a candidate JSON IR to check it, then deliver HTML.',
          inputSchema: {
            type: 'object',
            properties: {
              action: { type: 'string', enum: ['validate', 'deliver', 'compare'], description: 'Operation to run' },
              type: { type: 'string', enum: ['architecture', 'workflow', 'sequence', 'dataflow', 'lifecycle'], description: 'Diagram type' },
              input: { type: 'string', description: 'Path to the IR JSON (for compare: the base/before JSON)' },
              second: { type: 'string', description: 'For compare: the head/after JSON path' },
              output: { type: 'string', description: 'Output HTML path (deliver/compare)' }
            },
            required: ['action', 'type', 'input']
          },
          handler: async ({ action, type, input, second, output }) => {
            const renderer = findArchifyRenderer(directory);
            if (!renderer) {
              return {
                content: [{ type: 'text', text: 'archify renderer not found. Install it with `acts archify install` (or `acts setup --with-archify`).' }],
                isError: true
              };
            }
            const args = [renderer, action, type, input];
            if (action === 'compare') {
              if (!second) {
                return { content: [{ type: 'text', text: 'acts_archify: compare requires `second` (the head/after JSON path).' }], isError: true };
              }
              args.push(second);
            }
            if ((action === 'deliver' || action === 'compare') && output) args.push(output);
            if (action === 'validate' || action === 'deliver') args.push('--quality', 'showcase');
            args.push('--json');
            try {
              const result = execFileSync('node', args, {
                encoding: 'utf8',
                cwd: directory,
                timeout: 120000,
                stdio: ['pipe', 'pipe', 'pipe']
              });
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `acts_archify error: ${error.stderr || error.message}\n\nInstall the renderer with: acts archify install` }],
                isError: true
              };
            }
          }
        },

        // ─── Mode Tool ──────────────────────────
        acts_mode: {
          description: 'Control ACTS plugin mode. Modes: off (disable ACTS context), ' +
            'on (full context injection), strict (enforcement language). ' +
            'Use "enter" to activate, "exit" to deactivate, "status" to check current mode.',
          inputSchema: {
            type: 'object',
            properties: {
              action: { type: 'string', enum: ['enter', 'exit', 'status'], description: 'Action to perform' },
              level: { type: 'string', enum: ['on', 'strict'], description: 'Mode level when entering (default: on)' }
            },
            required: ['action']
          },
          handler: async ({ action, level = 'on' }) => {
            if (action === 'status') {
              return {
                content: [{
                  type: 'text',
                  text: `ACTS v2 Plugin Mode: ${pluginState.mode}\n` +
                        `Project: ${actsProject ? 'ACTS v2 initialized' : 'Not an ACTS v2 project'}\n` +
                        `Binary: ${actsBinary || 'not found'}\n` +
                        `Plugin Version: ${PLUGIN_VERSION}`
                }]
              };
            }
            if (action === 'enter') {
              if (!actsProject) {
                return {
                  content: [{ type: 'text', text: 'Error: Not an ACTS v2 project. Run `acts stack create <id>` first.' }],
                  isError: true
                };
              }
              const newMode = level === 'strict' ? 'strict' : 'on';
              pluginState.mode = newMode;
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              refreshStackStatus();
              return {
                content: [{
                  type: 'text',
                  text: `ACTS mode entered: ${newMode}\n\n` +
                        (newMode === 'strict'
                          ? 'Strict mode active. You MUST follow all verification gates and scope checks.'
                          : 'ACTS context will now be injected into conversations.')
                }]
              };
            }
            if (action === 'exit') {
              pluginState.mode = 'off';
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS mode exited. Context injection disabled. Run `acts_mode enter` to re-enable.'
                }]
              };
            }
          }
        }
      };
    },

    config: async () => {
      if (!actsBinary) {
        console.warn('[ACTS] Binary not found. Build it from acts-core or install it.');
        return;
      }
      if (!actsProject) {
        console.warn('[ACTS] No ACTS v2 project detected (.acts/stack.json missing). Run `acts stack create <id>`.');
        return;
      }
      console.log(`[ACTS] Plugin v${PLUGIN_VERSION} loaded. Mode: ${pluginState.mode}`);
      if (pluginState.mode !== 'off') {
        try {
          const status = refreshStackStatus();
          if (status) {
            console.log(`[ACTS] Stack: ${status.id} — ${status.title} (base: ${status.base_branch})`);
          }
        } catch (e) {
          console.warn('[ACTS] Failed to auto-read stack status:', e.message);
        }
      }
    }
  };
};
