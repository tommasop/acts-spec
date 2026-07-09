import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFileSync, execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─────────────────────────────────────────────
// ACTS OpenCode Plugin v2.0.0
// ─────────────────────────────────────────────

const PLUGIN_VERSION = '2.0.0';
const ACTS_VERSION = '1.0.0';

export const ActsPlugin = async ({ client, directory }) => {
  // ─── Binary Discovery ───────────────────────
  const findActsBinary = () => {
    const localPath = path.join(directory, '.acts', 'bin', 'acts');
    if (fs.existsSync(localPath)) {
      return localPath;
    }
    try {
      const which = execSync('which acts', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      return which.trim();
    } catch {
      return null;
    }
  };

  const actsBinary = findActsBinary();

  // ─── codebase-memory-mcp Discovery ──────────
  // Optional cross-repo code-intelligence backend. When present and OpenCode
  // `references` are configured, the plugin bridges ACTS state to a shared
  // knowledge graph spanning all referenced repos.
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

  const cbmBinary = findCbmBinary();
  const cbmCacheDir = path.join(directory, '.acts', 'cbm');

  // OpenCode `references` config (the cross-repo fleet)
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

  // Resolve a reference alias to an absolute path (local `path` only; git
  // `repository` references are materialized by OpenCode and not indexed here).
  const resolveRefPath = (alias) => {
    const ref = references[alias];
    if (!ref) return null;
    const p = ref.path;
    if (!p) return null;
    return path.resolve(directory, p);
  };

  // Spawn `codebase-memory-mcp cli <args>` against the per-project store.
  const runCbm = (cliArgs, opts = {}) => {
    if (!cbmBinary) {
      throw new Error(
        'codebase-memory-mcp not found. Install: ' +
        'curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash'
      );
    }
    const safeArgs = ['cli', ...cliArgs.map(a => String(a))];
    return execFileSync(cbmBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: opts.timeout || 120000,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, CBM_CACHE_DIR: cbmCacheDir },
      ...opts
    });
  };

  // Map an absolute file path to the reference alias it belongs to (longest
  // prefix match). Used to bridge ACTS task files → repos.
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

  // ─── Safe Command Runner ────────────────────
  const runActs = (args, options = {}) => {
    if (!actsBinary) {
      throw new Error('ACTS binary not found. Run `acts init <story-id>` to initialize.');
    }
    // Validate args are strings to prevent injection
    const safeArgs = args.map(a => String(a));
    return execFileSync(actsBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: options.timeout || 30000,
      stdio: ['pipe', 'pipe', 'pipe'],
      ...options
    });
  };

  // ─── Project Validation ─────────────────────
  const isActsProject = () => {
    return fs.existsSync(path.join(directory, '.acts', 'acts.db')) &&
           fs.existsSync(path.join(directory, '.acts', 'acts.json'));
  };

  const actsProject = isActsProject();

  // ─── Plugin State Management ────────────────
  const pluginStatePath = path.join(directory, '.acts', 'plugin-state.json');
  const overrideRequestsPath = path.join(directory, '.acts', 'override-requests.json');
  const overrideApprovalsPath = path.join(directory, '.acts', 'override-approvals.json');

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
      console.warn('Failed to save plugin state:', e.message);
    }
  };

  const pluginState = loadPluginState();

  // ─── Override Management ────────────────────
  const loadOverrides = () => {
    try {
      if (fs.existsSync(overrideRequestsPath)) {
        return JSON.parse(fs.readFileSync(overrideRequestsPath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { requests: [] };
  };

  const loadApprovals = () => {
    try {
      if (fs.existsSync(overrideApprovalsPath)) {
        return JSON.parse(fs.readFileSync(overrideApprovalsPath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { approvals: [] };
  };

  const saveOverrides = (data) => {
    try {
      fs.writeFileSync(overrideRequestsPath, JSON.stringify(data, null, 2));
    } catch (e) {
      console.warn('Failed to save override requests:', e.message);
    }
  };

  const saveApprovals = (data) => {
    try {
      fs.writeFileSync(overrideApprovalsPath, JSON.stringify(data, null, 2));
    } catch (e) {
      console.warn('Failed to save override approvals:', e.message);
    }
  };

  // ─── Dynamic Bootstrap from AGENTS.md ───────
  const getBootstrapContent = () => {
    const agentsPath = path.join(directory, 'AGENTS.md');
    let baseRules = '';

    if (fs.existsSync(agentsPath)) {
      try {
        const agentsContent = fs.readFileSync(agentsPath, 'utf8');
        // Extract ACTS Integration section if present
        const actsMatch = agentsContent.match(/## ACTS Integration[\s\S]*?(?=\n## |\n---|$)/);
        if (actsMatch) {
          baseRules = actsMatch[0].trim();
        }
      } catch { /* fall through to default */ }
    }

    if (!baseRules) {
      baseRules = `This project uses ACTS (Agent Collaborative Tracking Standard) v${ACTS_VERSION} for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: acts state read
- Agent MUST NOT modify files owned by completed tasks: acts scope check --task <id> --file <path>
- Agent MUST record session summary before ending: acts session validate <file.md>
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion`;
    }

    return `<EXTREMELY_IMPORTANT>
${baseRules}

ACTS Commands:
- acts init <story-id>              Initialize new ACTS story
- acts state read                   Read current story state
- acts state write --story <id>     Update story state (JSON from stdin)
- acts task get <task-id>           Get task details
- acts task update <id> --status <s> Update task status (enforces gates)
- acts gate add --task <id> --type <t> --status <s>  Add gate checkpoint
- acts approve <task-id>           Approve task-review gate (shorthand)
- acts reject <task-id> --reason   Reject task-review gate with reason (shorthand)
- acts gather-review <task-id>     Emit JSON review data for conversational review
- acts ownership map                Show file ownership
- acts scope check --task <id> --file <path> Check if file is safe to modify
- acts validate                     Validate entire ACTS project
- acts migrate                      Force schema migration

Gate Types:
- approve          Preflight approval (required before IN_PROGRESS)
- task-review      Code review approval (required before DONE)
- commit-review    Batch commit approval (strict mode)
- architecture-discuss Architecture decision approval (strict mode)

Status Values:
- TODO, IN_PROGRESS, BLOCKED, DONE (tasks)
- ANALYSIS, APPROVED, IN_PROGRESS, REVIEW, DONE (stories)
- pending, approved, changes_requested (gates)
</EXTREMELY_IMPORTANT>`;
  };

  // ─── Cached State ───────────────────────────
  let cachedState = null;
  let cachedOwnership = null;
  let cachedStateTime = 0;
  const STATE_CACHE_TTL = 60000; // 60 seconds

  const refreshState = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const now = Date.now();
      if (cachedState && (now - cachedStateTime) < STATE_CACHE_TTL) {
        return cachedState;
      }
      const raw = runActs(['state', 'read']);
      cachedState = JSON.parse(raw);
      cachedStateTime = now;
      return cachedState;
    } catch (e) {
      console.warn('Failed to read ACTS state:', e.message);
      return null;
    }
  };

  const refreshOwnership = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const raw = runActs(['ownership', 'map']);
      cachedOwnership = JSON.parse(raw);
      return cachedOwnership;
    } catch (e) {
      console.warn('Failed to read ownership map:', e.message);
      return null;
    }
  };

  // Initial load
  if (pluginState.mode !== 'off') {
    refreshState();
    refreshOwnership();
  }

  // ─── Context Builders ───────────────────────
  const buildSystemContext = () => {
    const state = refreshState();
    if (!state) return [];

    const lines = [];
    lines.push(`# ACTS Project Context`);
    lines.push(`- Story: ${state.story_id} (${state.title})`);
    lines.push(`- Story Status: ${state.status}`);
    lines.push(`- ACTS Mode: ${pluginState.mode}`);

    const inProgressTasks = (state.tasks || []).filter(t => t.status === 'IN_PROGRESS');
    if (inProgressTasks.length > 0) {
      lines.push(`## Active Tasks`);
      for (const task of inProgressTasks) {
        lines.push(`- ${task.id}: ${task.title} [${task.status}]`);
        if (task.description) lines.push(`  Description: ${task.description}`);
      }
    }

    // File ownership warnings
    const ownership = cachedOwnership || refreshOwnership();
    if (ownership && Object.keys(ownership).length > 0) {
      const doneOwned = Object.entries(ownership).filter(([, info]) => info.owner_status === 'DONE');
      if (doneOwned.length > 0) {
        lines.push(`## LOCKED Files (owned by DONE tasks — DO NOT MODIFY without override approval)`);
        for (const [file, info] of doneOwned) {
          lines.push(`- ${file} → owned by ${info.task_id}`);
        }
      }
    }

    // Approved overrides
    const approvals = loadApprovals();
    if (approvals.approvals && approvals.approvals.length > 0) {
      const active = approvals.approvals.filter(a => !a.expiresAt || new Date(a.expiresAt) > new Date());
      if (active.length > 0) {
        lines.push(`## Approved Overrides`);
        for (const ov of active) {
          lines.push(`- ${ov.file} (approved for ${ov.task}, reason: ${ov.reason})`);
        }
      }
    }

    // Cross-repo memory context (codebase-memory-mcp + OpenCode references)
    if (cbmBinary && Object.keys(references).length > 0) {
      lines.push(`## Cross-Repo Memory (codebase-memory-mcp)`);
      lines.push(`- Fleet repos (OpenCode references): ${Object.keys(references).join(', ')}`);
      lines.push(`- Use \`acts_memory\` tools for cross-repo tracing/impact (index-all, scope, trace, query, changes)`);
      const spanned = [];
      for (const task of inProgressTasks) {
        const files = task.files_touched || [];
        const repos = new Set();
        for (const f of files) {
          const abs = path.resolve(directory, f);
          const r = repoForFile(abs);
          if (r) repos.add(r);
        }
        if (repos.size) spanned.push(`  - ${task.id} spans: ${[...repos].join(', ')}`);
      }
      if (spanned.length) lines.push(...spanned);
    }

    if (pluginState.mode === 'strict') {
      lines.push(`## STRICT MODE ACTIVE`);
      lines.push(`- You MUST NOT write any code without a preflight gate approval.`);
      lines.push(`- You MUST NOT mark tasks DONE without task-review gate approval.`);
      lines.push(`- You MUST check acts scope check before modifying ANY file.`);
    }

    return [lines.join('\n')];
  };

  // ─── Hooks ──────────────────────────────────
  return {
    // Inject system-level ACTS context
    'experimental.chat.system.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      const context = buildSystemContext();
      if (context.length > 0) {
        output.system = [...output.system, ...context];
      }
    },

    // Inject ACTS bootstrap into first user message
    'experimental.chat.messages.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      if (!output.messages.length) return;

      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      // Only inject once per conversation
      const alreadyInjected = firstUser.parts.some(
        p => p.type === 'text' && p.text.includes('ACTS (Agent Collaborative Tracking Standard)')
      );
      if (alreadyInjected) return;

      const bootstrap = getBootstrapContent();
      firstUser.parts.unshift({ type: 'text', text: bootstrap });
    },

    // Register tools
    tools: async () => {
      if (!actsBinary) {
        return {
          acts_install: {
            description: 'Install ACTS in this project (no binary found)',
            inputSchema: {
              type: 'object',
              properties: {
                story_id: { type: 'string', description: 'Story ID to initialize after install' }
              }
            },
            handler: async ({ story_id }) => {
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS binary not found. Install with:\n' +
                        '  curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh | bash\n' +
                        'Then initialize: acts init ' + (story_id || '<story-id>')
                }]
              };
            }
          }
        };
      }

      return {
        // ─── Main ACTS Tool ─────────────────────
        acts: {
          description: 'Execute ACTS (Agent Collaborative Tracking Standard) commands. ' +
            'Common: state read, task get <id>, task update <id> --status <s>, ' +
            'gate add --task <id> --type <t> --status <s>, scope check --task <id> --file <path>, ' +
            'ownership map, validate',
          inputSchema: {
            type: 'object',
            properties: {
              command: {
                type: 'string',
                description: 'ACTS command to execute (e.g., "state read", "task update T1 --status DONE")'
              }
            },
            required: ['command']
          },
          handler: async ({ command }) => {
            try {
              // Parse command safely
              const args = command.trim().split(/\s+/);
              const result = runActs(args);
              return {
                content: [{ type: 'text', text: result }]
              };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}` }],
                isError: true
              };
            }
          }
        },

        // ─── Cross-Repo Memory Tool (codebase-memory-mcp) ──
        acts_memory: {
          description: 'Cross-repo code intelligence via codebase-memory-mcp. ' +
            'Bridges ACTS state to a shared knowledge graph of all OpenCode `references` repos. ' +
            'Subcommands: repos, index <alias>, index-all, status, query <cypher>, ' +
            'architecture, trace <function>, search <pattern>, changes, scope <task_id>.',
          inputSchema: {
            type: 'object',
            properties: {
              command: {
                type: 'string',
                description: 'acts_memory subcommand, e.g. "index-all" or "scope T3" or "trace ProcessOrder"'
              }
            },
            required: ['command']
          },
          handler: async ({ command }) => {
            const args = (command || '').trim().split(/\s+/).filter(Boolean);
            const sub = args[0];

            const err = (msg) => ({ content: [{ type: 'text', text: msg }], isError: true });

            try {
              switch (sub) {
                case 'repos': {
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
                  lines.push('Index with: acts_memory index-all');
                  return { content: [{ type: 'text', text: lines.join('\n') }] };
                }

                case 'index': {
                  const alias = args[1];
                  if (!alias) return err('Usage: acts_memory index <alias>');
                  const rp = resolveRefPath(alias);
                  if (!rp) return err(`Unknown reference alias "${alias}". Run: acts_memory repos`);
                  const out = runCbm(['index_repository', JSON.stringify({ repo_path: rp })]);
                  return { content: [{ type: 'text', text: `Indexed ${alias} (${rp}):\n${out}` }] };
                }

                case 'index-all': {
                  const aliases = Object.keys(references);
                  if (aliases.length === 0) return err('No `references` configured in opencode.json.');
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

                case 'status': {
                  const out = runCbm(['list_projects']);
                  return { content: [{ type: 'text', text: out }] };
                }

                case 'query': {
                  const cypher = args.slice(1).join(' ');
                  if (!cypher) return err('Usage: acts_memory query "MATCH (f:Function) RETURN f.name LIMIT 5"');
                  const out = runCbm(['query_graph', JSON.stringify({ query: cypher })]);
                  return { content: [{ type: 'text', text: out }] };
                }

                case 'architecture': {
                  const out = runCbm(['get_architecture', JSON.stringify({})]);
                  return { content: [{ type: 'text', text: out }] };
                }

                case 'trace': {
                  const rest = args.slice(1).join(' ');
                  if (!rest) return err('Usage: acts_memory trace <function_name|qualified_name>');
                  // Allow raw JSON payload or a plain function name.
                  let payload;
                  if (rest.trim().startsWith('{')) {
                    payload = rest;
                  } else {
                    payload = JSON.stringify({ function_name: rest, direction: 'both' });
                  }
                  const out = runCbm(['trace_path', payload]);
                  return { content: [{ type: 'text', text: out }] };
                }

                case 'search': {
                  const pat = args.slice(1).join(' ');
                  if (!pat) return err('Usage: acts_memory search "<name_pattern>"');
                  const out = runCbm(['search_graph', JSON.stringify({ name_pattern: pat })]);
                  return { content: [{ type: 'text', text: out }] };
                }

                case 'changes': {
                  const aliases = Object.keys(references);
                  if (aliases.length === 0) return err('No `references` configured in opencode.json.');
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

                case 'scope': {
                  const taskId = args[1];
                  if (!taskId) return err('Usage: acts_memory scope <task_id>');
                  const taskRaw = runActs(['task', 'get', taskId]);
                  const task = JSON.parse(taskRaw);
                  const files = task.files_touched || [];
                  const mapping = files.map(f => {
                    const abs = path.resolve(directory, f);
                    return { file: f, repo: repoForFile(abs) || 'unknown' };
                  });
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

                default:
                  return err(
                    'Unknown subcommand. Available: repos, index <alias>, index-all, status, ' +
                    'query <cypher>, architecture, trace <function>, search <pattern>, changes, scope <task_id>'
                  );
              }
            } catch (error) {
              return {
                content: [{ type: 'text', text: `acts_memory error: ${error.stderr || error.message}` }],
                isError: true
              };
            }
          }
        },

        // ─── ACTS Mode Tool ─────────────────────
        acts_mode: {
          description: 'Control ACTS plugin mode. Modes: off (disable ACTS context), ' +
            'on (full context injection), strict (enforcement language). ' +
            'Use "enter" to activate, "exit" to deactivate, "status" to check current mode.',
          inputSchema: {
            type: 'object',
            properties: {
              action: {
                type: 'string',
                enum: ['enter', 'exit', 'status'],
                description: 'Action to perform'
              },
              level: {
                type: 'string',
                enum: ['on', 'strict'],
                description: 'Mode level when entering (default: on)'
              }
            },
            required: ['action']
          },
          handler: async ({ action, level = 'on' }) => {
            if (action === 'status') {
              return {
                content: [{
                  type: 'text',
                  text: `ACTS Plugin Mode: ${pluginState.mode}\n` +
                        `Project: ${actsProject ? 'ACTS initialized' : 'Not an ACTS project'}\n` +
                        `Binary: ${actsBinary || 'not found'}\n` +
                        `Plugin Version: ${PLUGIN_VERSION}`
                }]
              };
            }

            if (action === 'enter') {
              if (!actsProject) {
                return {
                  content: [{ type: 'text', text: 'Error: Not an ACTS project. Run `acts init <story-id>` first.' }],
                  isError: true
                };
              }
              const newMode = level === 'strict' ? 'strict' : 'on';
              pluginState.mode = newMode;
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              refreshState();
              refreshOwnership();
              let enterText = `ACTS mode entered: ${newMode}\n\n` +
                (newMode === 'strict'
                  ? 'Strict mode active. You MUST follow all gate protocols and scope checks.'
                  : 'ACTS context will now be injected into conversations.');

              // Cross-repo memory hint
              if (cbmBinary && Object.keys(references).length > 0) {
                enterText += `\n\nCross-repo memory available (codebase-memory-mcp).\n` +
                  `Index the fleet with: acts_memory index-all\n` +
                  `Then use: acts_memory scope <task_id>, trace <fn>, query <cypher>, changes`;
              }

              return {
                content: [{
                  type: 'text',
                  text: enterText
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
        },

        // ─── Override Tool ──────────────────────
        acts_override: {
          description: 'Request or check file override approvals for files locked by DONE tasks. ' +
            'HUMAN DEVELOPER APPROVAL IS REQUIRED for all overrides. ' +
            'Actions: request (create request), check (check approval status), list (show all).',
          inputSchema: {
            type: 'object',
            properties: {
              action: {
                type: 'string',
                enum: ['request', 'check', 'list', 'approve'],
                description: 'Override action'
              },
              file: {
                type: 'string',
                description: 'File path to request override for (required for request)'
              },
              task: {
                type: 'string',
                description: 'Current task ID requesting override (required for request)'
              },
              reason: {
                type: 'string',
                description: 'Reason for override (required for request)'
              },
              override_id: {
                type: 'string',
                description: 'Override ID to check or approve'
              }
            },
            required: ['action']
          },
          handler: async ({ action, file, task, reason, override_id }) => {
            const requests = loadOverrides();
            const approvals = loadApprovals();

            if (action === 'request') {
              if (!file || !task || !reason) {
                return {
                  content: [{ type: 'text', text: 'Error: file, task, and reason are required for request.' }],
                  isError: true
                };
              }

              // Check scope first
              try {
                const scopeResult = runActs(['scope', 'check', '--task', task, '--file', file]);
                const scope = JSON.parse(scopeResult);
                if (scope.action === 'ok' && !scope.owned_by) {
                  return {
                    content: [{
                      type: 'text',
                      text: `File ${file} is not locked by any task. No override needed.`
                    }]
                  };
                }
              } catch { /* proceed anyway */ }

              const id = 'ovr-' + Date.now().toString(36);
              const request = {
                id,
                file,
                task,
                reason,
                requestedAt: new Date().toISOString(),
                status: 'pending'
              };
              requests.requests = requests.requests || [];
              requests.requests.push(request);
              saveOverrides(requests);

              return {
                content: [{
                  type: 'text',
                  text: `Override requested: ${id}\n` +
                        `File: ${file}\n` +
                        `Task: ${task}\n` +
                        `Reason: ${reason}\n\n` +
                        `⚠️ HUMAN APPROVAL REQUIRED ⚠️\n\n` +
                        `The developer must approve this override before you can modify this file.\n` +
                        `To approve, the developer should run:\n` +
                        `  acts_override approve --override_id ${id}\n` +
                        `Or edit .acts/override-approvals.json manually.\n\n` +
                        `You can check status with:\n` +
                        `  acts_override check --override_id ${id}`
                }]
              };
            }

            if (action === 'check') {
              if (!override_id) {
                return {
                  content: [{ type: 'text', text: 'Error: override_id is required for check.' }],
                  isError: true
                };
              }
              const approved = (approvals.approvals || []).find(a => a.id === override_id);
              if (approved) {
                return {
                  content: [{
                    type: 'text',
                    text: `Override ${override_id}: APPROVED ✅\n` +
                          `File: ${approved.file}\n` +
                          `Approved at: ${approved.approvedAt}\n` +
                          `Approved by: ${approved.approvedBy || 'unknown'}\n` +
                          `Reason: ${approved.reason}\n` +
                          (approved.expiresAt ? `Expires: ${approved.expiresAt}\n` : '') +
                          `\nYou may now modify this file.`
                  }]
                };
              }
              const pending = (requests.requests || []).find(r => r.id === override_id);
              if (pending) {
                return {
                  content: [{
                    type: 'text',
                    text: `Override ${override_id}: PENDING ⏳\n` +
                          `File: ${pending.file}\n` +
                          `Requested at: ${pending.requestedAt}\n` +
                          `Reason: ${pending.reason}\n\n` +
                          `Waiting for human developer approval.`
                  }]
                };
              }
              return {
                content: [{ type: 'text', text: `Override ${override_id}: NOT FOUND` }]
              };
            }

            if (action === 'list') {
              const pending = (requests.requests || []).filter(r => r.status === 'pending');
              const approved = (approvals.approvals || []).filter(a => !a.expiresAt || new Date(a.expiresAt) > new Date());
              let text = '## Override Requests\n\n';
              if (pending.length === 0 && approved.length === 0) {
                text += 'No override requests or approvals.\n';
              } else {
                if (pending.length > 0) {
                  text += '### Pending\n';
                  for (const r of pending) {
                    text += `- ${r.id}: ${r.file} (task: ${r.task}, reason: ${r.reason})\n`;
                  }
                  text += '\n';
                }
                if (approved.length > 0) {
                  text += '### Approved\n';
                  for (const a of approved) {
                    text += `- ${a.id}: ${a.file} (task: ${a.task}, reason: ${a.reason})\n`;
                  }
                }
              }
              return { content: [{ type: 'text', text }] };
            }

            if (action === 'approve') {
              // This action is intended for HUMAN DEVELOPERS, not the agent.
              // The agent should NOT call this. We allow it but warn strongly.
              if (!override_id) {
                return {
                  content: [{ type: 'text', text: 'Error: override_id is required for approve.' }],
                  isError: true
                };
              }
              const request = (requests.requests || []).find(r => r.id === override_id);
              if (!request) {
                return {
                  content: [{ type: 'text', text: `Error: Override request ${override_id} not found.` }],
                  isError: true
                };
              }

              const approval = {
                id: override_id,
                file: request.file,
                task: request.task,
                reason: request.reason,
                requestedAt: request.requestedAt,
                approvedAt: new Date().toISOString(),
                approvedBy: 'developer-via-plugin',
                expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24h expiry
              };

              approvals.approvals = approvals.approvals || [];
              approvals.approvals.push(approval);
              saveApprovals(approvals);

              // Update request status
              request.status = 'approved';
              saveOverrides(requests);

              return {
                content: [{
                  type: 'text',
                  text: `Override ${override_id}: APPROVED ✅\n` +
                        `File: ${approval.file}\n` +
                        `Task: ${approval.task}\n` +
                        `Expires: ${approval.expiresAt}\n\n` +
                        `⚠️ WARNING: This action should only be performed by a human developer. ` +
                        `If you are an AI agent, you MUST NOT have called this. ` +
                        `Approval has been logged for audit.`
                }]
              };
            }
          }
        },

        // ─── Review Tool (Conversational) ──────
        acts_review: {
          description: 'Gather review data for a task for conversational human review. ' +
            'Runs gather-review, formats each file with properly diffed hunk lines. ' +
            'Returns structured data per file: file_path, additions, deletions, risk, annotation, and full diff. ' +
            'The agent should then present each file to the human via the question tool.',
          inputSchema: {
            type: 'object',
            properties: {
              task_id: {
                type: 'string',
                description: 'Task ID to review (e.g., T1)'
              }
            },
            required: ['task_id']
          },
          handler: async ({ task_id }) => {
            if (!task_id) {
              return {
                content: [{ type: 'text', text: 'Error: task_id is required.' }],
                isError: true
              };
            }

            // Run gather-review to get structured data
            let raw;
            try {
              raw = runActs(['gather-review', task_id]);
            } catch (error) {
              return {
                content: [{ type: 'text', text: `Error running gather-review: ${error.stderr || error.message}` }],
                isError: true
              };
            }

            let data;
            try {
              data = JSON.parse(raw);
            } catch {
              return {
                content: [{ type: 'text', text: 'Error: gather-review output is not valid JSON.' }],
                isError: true
              };
            }

            // Build structured output for the agent
            const parts = [];

            // Summary header
            let summary = `# Review: ${data.task_id}\n\n`;
            summary += `**Title:** ${data.task_title}\n`;
            if (data.rationale) {
              summary += `**Rationale:** ${data.rationale}\n`;
            }
            if (data.rejections && data.rejections.length > 0) {
              summary += `**Previous rejections:** ${data.rejections.length}\n`;
              for (const r of data.rejections) {
                summary += `- ${r.approved_by} (${r.created_at}): ${r.comment || 'no comment'}\n`;
              }
            }
            parts.push({ type: 'text', text: summary });

            // Quality results summary
            if (data.quality_results && data.quality_results.length > 0) {
              let qText = '## Quality Gates\n\n';
              qText += '| Stage | Status | Exit Code | Command |\n';
              qText += '|-------|--------|-----------|--------|\n';
              for (const qr of data.quality_results) {
                const statusIcon = qr.status === 'pass' ? '✅' : qr.status === 'fail' ? '❌' : '⏭️';
                qText += `| ${qr.stage} | ${statusIcon} ${qr.status} | ${qr.exit_code} | \`${qr.command}\` |\n`;
              }
              parts.push({ type: 'text', text: qText });
            }

            // Per-file review with diffs
            if (data.files && data.files.length > 0) {
              for (const file of data.files) {
                let fileText = `## File: ${file.file_path}\n\n`;
                fileText += `**Changes:** +${file.additions} / -${file.deletions}\n`;
                fileText += `**Risk:** ${file.risk}\n`;
                if (file.annotation) {
                  fileText += `**Annotation:** ${file.annotation}\n`;
                }
                fileText += '\n';

                // Format hunks as proper diff
                if (file.hunks && file.hunks.length > 0) {
                  for (const hunk of file.hunks) {
                    fileText += '```diff\n';
                    fileText += `${hunk.header}\n`;
                    fileText += `${hunk.lines}`;
                    if (!hunk.lines.endsWith('\n')) fileText += '\n';
                    fileText += '```\n\n';
                  }
                }

                parts.push({ type: 'text', text: fileText });
              }
            } else {
              parts.push({ type: 'text', text: 'No files changed in this task.\n' });
            }

            // Instructions for agent
            parts.push({
              type: 'text',
              text: '## Review Instructions\n\n' +
                'Present each file above to the human using the question tool. ' +
                'For each file, ask "Approve this file?" ' +
                'Collect per-file decisions. ' +
                'When all files are approved, run: `acts gate add --task TASK_ID --type task-review --status approved`\n' +
                'To reject with changes: `acts reject TASK_ID --reason "..."`\n'
            });

            return { content: parts };
          }
        }
      };
    },

    // ─── Config Hook ──────────────────────────
    config: async (config) => {
      if (!actsBinary) {
        console.warn('[ACTS] Binary not found. Run `acts init <story-id>` to initialize.');
        return;
      }
      if (!actsProject) {
        console.warn('[ACTS] Binary found but no ACTS project detected (.acts/acts.db missing).');
        return;
      }
      console.log(`[ACTS] Plugin v${PLUGIN_VERSION} loaded. Mode: ${pluginState.mode}`);
      if (pluginState.mode !== 'off') {
        try {
          const state = refreshState();
          if (state) {
            console.log(`[ACTS] Story: ${state.story_id} (${state.status})`);
            const activeTasks = (state.tasks || []).filter(t => t.status === 'IN_PROGRESS');
            if (activeTasks.length > 0) {
              console.log(`[ACTS] Active tasks: ${activeTasks.map(t => t.id).join(', ')}`);
            }
          }
        } catch (e) {
          console.warn('[ACTS] Failed to auto-read state:', e.message);
        }
      }
    }
  };
};
