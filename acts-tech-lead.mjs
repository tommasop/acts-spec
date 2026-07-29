#!/usr/bin/env node
/**
 * acts-tech-lead — Standalone CLI for tech lead pre-flight analysis
 *
 * Usage:
 *   node acts-tech-lead.mjs <task_id> [--depth 3] [--risk-threshold MEDIUM]
 *
 * Reads ACTS task context, resolves symbols via codebase-memory-mcp,
 * traces call chains with risk classification, and prints a report.
 */

import path from 'path';
import fs from 'fs';
import { execFileSync } from 'child_process';

const directory = process.cwd();
const cbmCacheDir = path.join(process.env.HOME || '~', '.cache', 'codebase-memory-mcp');
const cbmBinary = path.join(directory, '.acts', 'bin', 'codebase-memory-mcp');
const actsBinary = path.join(directory, '.acts', 'bin', 'acts');

// Parse args
const args = process.argv.slice(2);
let taskId = null;
let depth = 3;
let riskThreshold = 'MEDIUM';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--depth') depth = parseInt(args[++i], 10);
  else if (args[i] === '--risk-threshold') riskThreshold = args[++i];
  else if (!taskId) taskId = args[i];
}

if (!taskId) {
  console.error('Usage: acts-tech-lead <task_id> [--depth 3] [--risk-threshold MEDIUM]');
  process.exit(1);
}

const runCbm = (cliArgs) => {
  return execFileSync(cbmBinary, ['cli', ...cliArgs], {
    encoding: 'utf8',
    cwd: directory,
    timeout: 120000,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, CBM_CACHE_DIR: cbmCacheDir }
  });
};

const runActs = (actsArgs) => {
  return execFileSync(actsBinary, actsArgs, {
    encoding: 'utf8',
    cwd: directory,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe']
  });
};

const RISK_ORDER = { CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1 };
const threshold = RISK_ORDER[riskThreshold] || 2;

// 1. Read ACTS task
let task;
try {
  const state = JSON.parse(runActs(['state', 'read']));
  task = (state.tasks || []).find(t => t.id === taskId);
  if (!task) {
    console.error(`Task ${taskId} not found in story ${state.story_id}`);
    process.exit(1);
  }
} catch (e) {
  console.error(`Failed to read ACTS state: ${e.stderr || e.message}`);
  process.exit(1);
}

const files = task.files_touched || [];
if (files.length === 0) {
  console.log(`# Tech Lead Pre-Flight Report: ${taskId}\n`);
  console.log(`**Task:** ${task.title}`);
  console.log(`**Status:** ${task.status}\n`);
  console.log('No files_touched recorded for this task yet.');
  process.exit(0);
}

// 2. Map files to CBM projects
const references = (() => {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(directory, 'opencode.json'), 'utf8'));
    return cfg.references || {};
  } catch { return {}; }
})();

const resolveRefPath = (alias) => {
  const ref = references[alias];
  if (!ref || !ref.path) return null;
  return path.resolve(directory, ref.path);
};

const listProjects = () => {
  try {
    const raw = runCbm(['list_projects', '{}']);
    return JSON.parse(raw).projects || [];
  } catch { return []; }
};

const projectForRepo = (repoAlias) => {
  const rp = resolveRefPath(repoAlias);
  if (!rp) return null;
  const projects = listProjects();
  const basename = path.basename(rp);
  const match = projects.find(p => {
    const projRoot = p.root_path || p.canonical_root || '';
    return projRoot === rp || projRoot.includes(basename);
  });
  return match ? match.name : null;
};

const repoForFile = (absFile) => {
  // First pass: match against OpenCode references
  for (const alias of Object.keys(references)) {
    const rp = resolveRefPath(alias);
    if (rp && absFile.startsWith(rp + path.sep)) return alias;
  }
  // Second pass: match against CBM project root_paths
  const allProjects = listProjects();
  for (const p of allProjects) {
    const projRoot = p.root_path || p.canonical_root || '';
    if (projRoot && absFile.startsWith(projRoot + path.sep)) {
      for (const alias of Object.keys(references)) {
        const rp = resolveRefPath(alias);
        if (rp && projRoot.includes(path.basename(rp || ''))) return alias;
      }
      return p.name;
    }
  }
  return null;
};

const fileMapping = files.map(f => {
  const absPath = path.resolve(directory, f);
  const repo = repoForFile(absPath);
  const project = repo ? projectForRepo(repo) : null;
  return { file: f, absPath, repo: repo || 'unknown', project };
});

// 3. Search symbols per file
const allSymbols = [];
const crossRepoImpact = [];
const errors = [];

for (const fm of fileMapping) {
  if (!fm.project) {
    errors.push(`${fm.file}: repo "${fm.repo}" not indexed in CBM`);
    continue;
  }

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

    const callerCount = (trace.callers || []).length;
    const calleeCount = (trace.callees || []).length;
    const totalConnections = callerCount + calleeCount;

    const allProjects = listProjects();
    const projectNames = allProjects.map(p => p.name);
    const isCrossRepo = (s) => {
      const qn = s.qualified_name || '';
      return projectNames.some(pn => qn.startsWith(pn + '.') && pn !== fm.project);
    };
    const crossCallers = (trace.callers || []).filter(isCrossRepo);
    const crossCallees = (trace.callees || []).filter(isCrossRepo);

    let risk = 'LOW';
    if (crossCallers.length > 0 || crossCallees.length > 0) {
      risk = (crossCallers.length >= 2 || crossCallees.length >= 2) ? 'CRITICAL' : 'HIGH';
    } else if (totalConnections >= 5 || (sym.complexity || 0) > 15) {
      risk = 'HIGH';
    } else if (totalConnections >= 3 || (sym.complexity || 0) > 8) {
      risk = 'MEDIUM';
    }

    if (RISK_ORDER[risk] < threshold) continue;

    for (const cc of crossCallers) {
      crossRepoImpact.push({ source: sym.name, target: cc.name, type: 'INBOUND', risk });
    }
    for (const cc of crossCallees) {
      crossRepoImpact.push({ source: sym.name, target: cc.name, type: 'OUTBOUND', risk });
    }

    allSymbols.push({
      file: fm.file, repo: fm.repo, name: sym.name, risk,
      callers: callerCount, callees: calleeCount,
      complexity: sym.complexity || 0
    });
  }
}

// Output report
console.log(`# Tech Lead Pre-Flight Report: ${taskId}\n`);
console.log(`**Task:** ${task.title}`);
console.log(`**Status:** ${task.status}`);
console.log(`**Analyzed:** ${new Date().toISOString()}`);
console.log(`**Files:** ${fileMapping.length} | **Symbols:** ${allSymbols.length} | **Depth:** ${depth}\n`);

const riskSummary = { CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0 };
allSymbols.forEach(s => riskSummary[s.risk]++);

console.log('## Risk Summary\n');
console.log('| Level | Count |');
console.log('|-------|-------|');
console.log(`| CRITICAL | ${riskSummary.CRITICAL} |`);
console.log(`| HIGH | ${riskSummary.HIGH} |`);
console.log(`| MEDIUM | ${riskSummary.MEDIUM} |`);
console.log(`| LOW | ${riskSummary.LOW} |\n`);

if (crossRepoImpact.length > 0) {
  console.log('## Cross-Repo Impact\n');
  for (const impact of crossRepoImpact) {
    const icon = impact.risk === 'CRITICAL' ? '🔴' : impact.risk === 'HIGH' ? '🟠' : '🟡';
    console.log(`${icon} **${impact.risk}** \`${impact.source}\` → \`${impact.target}\``);
    console.log(`   Edge: ${impact.type}\n`);
  }
}

const byFile = {};
allSymbols.forEach(s => {
  if (!byFile[s.file]) byFile[s.file] = { repo: s.repo, symbols: [] };
  byFile[s.file].symbols.push(s);
});

if (Object.keys(byFile).length > 0) {
  console.log('## Per-File Analysis\n');
  for (const [file, data] of Object.entries(byFile)) {
    console.log(`### ${file} (${data.repo})\n`);
    console.log('| Symbol | Risk | Callers | Callees | Complexity |');
    console.log('|--------|------|---------|---------|------------|');
    for (const s of data.symbols) {
      console.log(`| ${s.name} | ${s.risk} | ${s.callers} | ${s.callees} | ${s.complexity} |`);
    }
    console.log('');
  }
}

if (errors.length > 0) {
  console.log('## Warnings\n');
  errors.forEach(e => console.log(`- ${e}`));
  console.log('');
}
