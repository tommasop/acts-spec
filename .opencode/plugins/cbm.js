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

  // CBM cache directory: prefer .acts/cbm if indexed there, else fall back to default
  const defaultCacheDir = path.join(process.env.HOME || '~', '.cache', 'codebase-memory-mcp');
  const localCacheDir = path.join(directory, '.acts', 'cbm');
  const cbmCacheDir = fs.existsSync(localCacheDir) ? localCacheDir : defaultCacheDir;

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
  // Also checks CBM project root_paths as fallback for path mismatches.
  const repoForFile = (absFile) => {
    let best = null;
    // First pass: match against OpenCode references
    for (const alias of Object.keys(references)) {
      const rp = resolveRefPath(alias);
      if (rp && absFile.startsWith(rp + path.sep)) {
        if (!best || rp.length > best.length) best = alias;
      }
    }
    if (best) return best;

    // Second pass: match against CBM indexed project root_paths
    try {
      const projects = listProjects();
      for (const p of projects) {
        const projRoot = p.root_path || p.canonical_root || '';
        if (projRoot && absFile.startsWith(projRoot + path.sep)) {
          // Find matching alias by path or name
          for (const alias of Object.keys(references)) {
            const rp = resolveRefPath(alias);
            if (rp && projRoot.includes(path.basename(rp))) {
              return alias;
            }
          }
          // Fallback: use project name as alias
          return p.name;
        }
      }
    } catch { /* ignore */ }

    return best;
  };

  // ─── Repo Alias → CBM Project Name Mapping ──
  const listProjects = () => {
    try {
      const raw = runCbm(['list_projects', '{}']);
      const data = JSON.parse(raw);
      return data.projects || [];
    } catch {
      return [];
    }
  };

  const projectForRepo = (repoAlias) => {
    const rp = resolveRefPath(repoAlias);
    if (!rp) return null;
    const projects = listProjects();
    const basename = path.basename(rp);
    // Match by root_path (canonical, resolved, or basename)
    const match = projects.find(p => {
      const projRoot = p.root_path || p.canonical_root || '';
      return projRoot === rp ||
             projRoot === path.resolve(directory, rp) ||
             projRoot.includes(basename);
    });
    return match ? match.name : null;
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
    },

    // ─── Tech Lead Pre-Flight Analysis ────────
    acts_tech_lead_analysis: {
      description: 'Pre-flight risk report: combines ACTS task context with CBM graph intelligence. ' +
        'Traces call chains with risk classification, identifies cross-repo impact, and produces ' +
        'a structured report for tech lead review before coding begins.',
      inputSchema: {
        type: 'object',
        properties: {
          task_id: { type: 'string', description: 'ACTS task ID to analyze (e.g., T1)' },
          depth: { type: 'number', description: 'Call chain trace depth (default: 3)' },
          risk_threshold: {
            type: 'string',
            enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'],
            description: 'Minimum risk level to include in report (default: MEDIUM)'
          }
        },
        required: ['task_id']
      },
      handler: async ({ task_id, depth = 3, risk_threshold = 'MEDIUM' }) => {
        const err = (m) => ({ content: [{ type: 'text', text: m }], isError: true });

        const RISK_ORDER = { CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1 };
        const threshold = RISK_ORDER[risk_threshold] || 2;

        if (!actsBinary) return err('ACTS binary not found. Cannot read task context.');
        if (!cbmBinary && !ensureCbm().ok) {
          return err('codebase-memory-mcp not available. Run `cbm_install` first.');
        }

        // ─── Step 1: Read ACTS task context ──────
        // Note: `acts task get` doesn't return files_touched, so we read from state
        let task;
        try {
          const state = JSON.parse(runActs(['state', 'read']));
          task = (state.tasks || []).find(t => t.id === task_id);
          if (!task) {
            return err(`Task ${task_id} not found in story ${state.story_id}`);
          }
        } catch (e) {
          return err(`Failed to read ACTS state: ${e.stderr || e.message}`);
        }

        const files = task.files_touched || [];
        if (files.length === 0) {
          return {
            content: [{
              type: 'text',
              text: `# Tech Lead Pre-Flight Report: ${task_id}\n\n` +
                `**Task:** ${task.title}\n` +
                `**Status:** ${task.status}\n\n` +
                `No files_touched recorded for this task yet. ` +
                `Add files to the task before running analysis.`
            }]
          };
        }

        // ─── Step 2: Map files → repos → CBM projects ──
        const fileMapping = files.map(f => {
          const absPath = path.resolve(directory, f);
          const repo = repoForFile(absPath);
          const project = repo ? projectForRepo(repo) : null;
          return { file: f, absPath, repo: repo || 'unknown', project };
        });

        // ─── Step 3: Search for symbols per file ──────
        const allSymbols = [];
        const crossRepoImpact = [];
        const errors = [];

        for (const fm of fileMapping) {
          if (!fm.project) {
            errors.push(`${fm.file}: repo "${fm.repo}" not indexed in CBM`);
            continue;
          }

          // Search for functions in this file
          let searchResult;
          try {
            const raw = runCbm(['search_graph', JSON.stringify({
              project: fm.project,
              file_path: fm.file,
              label: 'Function',
              limit: 50
            })]);
            searchResult = JSON.parse(raw);
          } catch (e) {
            errors.push(`${fm.file}: search_graph failed — ${e.message}`);
            continue;
          }

          const symbols = searchResult.results || [];
          if (symbols.length === 0) continue;

          // ─── Step 4: Trace call paths per symbol ──
          for (const sym of symbols) {
            let trace;
            try {
              const raw = runCbm(['trace_path', JSON.stringify({
                project: fm.project,
                function_name: sym.name,
                direction: 'both',
                depth,
                risk_labels: true,
                mode: 'cross_service'
              })]);
              trace = JSON.parse(raw);
            } catch (e) {
              errors.push(`${sym.qualified_name}: trace_path failed — ${e.message}`);
              continue;
            }

            // Classify risk from trace data
            const callerCount = (trace.callers || []).length;
            const calleeCount = (trace.callees || []).length;
            const totalConnections = callerCount + calleeCount;

            // Check for cross-repo edges by matching qualified_name prefix against known projects
            const allProjects = listProjects();
            const projectNames = allProjects.map(p => p.name);
            const isCrossRepo = (sym) => {
              const qn = sym.qualified_name || '';
              // A symbol is cross-repo if its qualified_name starts with a DIFFERENT project name
              return projectNames.some(pn => qn.startsWith(pn + '.') && pn !== fm.project);
            };
            const crossCallers = (trace.callers || []).filter(isCrossRepo);
            const crossCallees = (trace.callees || []).filter(isCrossRepo);

            // Determine risk level
            let risk = 'LOW';
            if (crossCallers.length > 0 || crossCallees.length > 0) {
              if (crossCallers.length >= 2 || crossCallees.length >= 2) {
                risk = 'CRITICAL';
              } else {
                risk = 'HIGH';
              }
            } else if (totalConnections >= 5 || (sym.complexity || 0) > 15) {
              risk = 'HIGH';
            } else if (totalConnections >= 3 || (sym.complexity || 0) > 8) {
              risk = 'MEDIUM';
            }

            const riskScore = RISK_ORDER[risk];
            if (riskScore < threshold) continue;

            // Collect cross-repo impact entries
            const findRepoForSymbol = (sym) => {
              const qn = sym.qualified_name || '';
              for (const p of allProjects) {
                if (qn.startsWith(p.name + '.')) {
                  // Find matching alias
                  for (const alias of Object.keys(references)) {
                    const rp = resolveRefPath(alias);
                    if (rp && (p.root_path || '').includes(path.basename(rp || ''))) {
                      return alias;
                    }
                  }
                  return p.name;
                }
              }
              return 'unknown';
            };

            for (const cc of crossCallers) {
              crossRepoImpact.push({
                source_repo: fm.repo,
                source_symbol: sym.name,
                target_repo: findRepoForSymbol(cc),
                target_symbol: cc.name,
                edge_type: 'INBOUND',
                risk
              });
            }
            for (const cc of crossCallees) {
              crossRepoImpact.push({
                source_repo: fm.repo,
                source_symbol: sym.name,
                target_repo: findRepoForSymbol(cc),
                target_symbol: cc.name,
                edge_type: 'OUTBOUND',
                risk
              });
            }

            allSymbols.push({
              file: fm.file,
              repo: fm.repo,
              name: sym.name,
              qualified_name: sym.qualified_name,
              risk,
              callers: (trace.callers || []).map(c => c.name),
              callees: (trace.callees || []).map(c => c.name),
              cross_repo_callers: crossCallers.map(c => c.name),
              cross_repo_callees: crossCallees.map(c => c.name),
              complexity: sym.complexity || 0,
              lines: sym.lines || 0,
              in_degree: sym.in_degree || 0,
              out_degree: sym.out_degree || 0
            });
          }
        }

        // ─── Step 5: Blast radius (detect_changes) ──
        let blastRadius = { changed_files: 0, impacted_symbols: 0 };
        const seenProjects = [...new Set(fileMapping.filter(f => f.project).map(f => f.project))];
        for (const proj of seenProjects) {
          try {
            const raw = runCbm(['detect_changes', JSON.stringify({ project: proj })]);
            const data = JSON.parse(raw);
            blastRadius.changed_files += (data.changed_files || []).length;
            blastRadius.impacted_symbols += (data.impacted_symbols || []).length;
          } catch { /* best effort */ }
        }

        // ─── Step 6: Aggregate results ─────────────
        const riskSummary = { CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0 };
        for (const s of allSymbols) riskSummary[s.risk]++;

        // ─── Step 7: Build markdown report ─────────
        const lines = [];
        lines.push(`# Tech Lead Pre-Flight Report: ${task_id}`);
        lines.push('');
        lines.push(`**Task:** ${task.title}`);
        lines.push(`**Status:** ${task.status}`);
        if (task.description) lines.push(`**Description:** ${task.description}`);
        lines.push(`**Analyzed:** ${new Date().toISOString()}`);
        lines.push(`**Files:** ${fileMapping.length} | **Symbols:** ${allSymbols.length} | **Depth:** ${depth}`);
        lines.push('');

        // Risk summary
        lines.push('## Risk Summary');
        lines.push('');
        lines.push('| Level | Count |');
        lines.push('|-------|-------|');
        lines.push(`| CRITICAL | ${riskSummary.CRITICAL} |`);
        lines.push(`| HIGH | ${riskSummary.HIGH} |`);
        lines.push(`| MEDIUM | ${riskSummary.MEDIUM} |`);
        lines.push(`| LOW | ${riskSummary.LOW} |`);
        lines.push('');

        // Cross-repo impact
        if (crossRepoImpact.length > 0) {
          lines.push('## Cross-Repo Impact');
          lines.push('');
          for (const impact of crossRepoImpact) {
            const icon = impact.risk === 'CRITICAL' ? '🔴' : impact.risk === 'HIGH' ? '🟠' : '🟡';
            lines.push(`${icon} **${impact.risk}** \`${impact.source_repo}.${impact.source_symbol}\` → \`${impact.target_symbol}\``);
            lines.push(`   Edge: ${impact.edge_type}`);
            lines.push('');
          }
        }

        // Per-file analysis
        const byFile = {};
        for (const s of allSymbols) {
          if (!byFile[s.file]) byFile[s.file] = { repo: s.repo, symbols: [] };
          byFile[s.file].symbols.push(s);
        }

        if (Object.keys(byFile).length > 0) {
          lines.push('## Per-File Analysis');
          lines.push('');
          for (const [file, data] of Object.entries(byFile)) {
            lines.push(`### ${file} (${data.repo})`);
            lines.push('');
            lines.push('| Symbol | Risk | Callers | Callees | Cross-Repo | Complexity |');
            lines.push('|--------|------|---------|---------|------------|------------|');
            for (const s of data.symbols) {
              const crossCount = s.cross_repo_callers.length + s.cross_repo_callees.length;
              const crossStr = crossCount > 0 ? `${crossCount} edge${crossCount > 1 ? 's' : ''}` : '—';
              lines.push(`| ${s.name} | ${s.risk} | ${s.callers.length} | ${s.callees.length} | ${crossStr} | ${s.complexity} |`);
            }
            lines.push('');
          }
        }

        // Blast radius
        if (blastRadius.changed_files > 0 || blastRadius.impacted_symbols > 0) {
          lines.push('## Blast Radius');
          lines.push('');
          lines.push(`- Changed files: ${blastRadius.changed_files}`);
          lines.push(`- Impacted symbols: ${blastRadius.impacted_symbols}`);
          lines.push('');
        }

        // Errors
        if (errors.length > 0) {
          lines.push('## Warnings');
          lines.push('');
          for (const e of errors) {
            lines.push(`- ${e}`);
          }
          lines.push('');
        }

        // Instructions for LLM
        lines.push('---');
        lines.push('');
        lines.push('*Interpret this data to provide actionable recommendations. ' +
          'Focus on: deployment coordination for cross-repo impacts, ' +
          'backward compatibility for high-caller-count symbols, ' +
          'and code review priorities for high-complexity functions.*');

        return { content: [{ type: 'text', text: lines.join('\n') }] };
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
