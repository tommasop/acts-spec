#!/usr/bin/env node
/**
 * acts-zeplin-contract — Extract API contract from Zeplin flow designs
 *
 * Usage:
 *   node acts-zeplin-contract.mjs --flow "https://app.zeplin.io/project/abc/flow/xyz"
 *   node acts-zeplin-contract.mjs --flow "https://app.zeplin.io/project/abc/flow/xyz" --json
 *   node acts-zeplin-contract.mjs --flow "https://app.zeplin.io/project/abc/flow/xyz" --notes
 *
 * Reads the Zeplin flow board via REST API, analyzes screen layers for
 * form fields / buttons / labels, and outputs an inferred API contract.
 *
 * Auth: reads ZEPLIN_ACCESS_TOKEN from env, or falls back to opencode.json config.
 */

import path from 'path';
import fs from 'fs';

// ─── CLI ────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
let flowUrl = null;
let outputJson = false;
let includeNotes = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--flow') flowUrl = args[++i];
  else if (args[i] === '--json') outputJson = true;
  else if (args[i] === '--notes') includeNotes = true;
  else if (args[i] === '--help' || args[i] === '-h') {
    console.log(`Usage: acts-zeplin-contract --flow <zeplin-flow-url> [--json] [--notes]

Options:
  --flow <url>   Zeplin flow URL (required)
  --json         Output raw JSON instead of markdown
  --notes        Fetch screen notes and annotations (slower)
  --help         Show this message`);
    process.exit(0);
  }
}

if (!flowUrl) {
  console.error('Error: --flow <url> is required. Run with --help for usage.');
  process.exit(1);
}

// ─── URL Parsing ────────────────────────────────────────────────────────

function parseFlowUrl(url) {
  // https://app.zeplin.io/project/{project_id}/flow/{flow_board_id}
  // or https://app.zeplin.io/project/{project_id}/flow/{flow_board_id}?name=...
  const match = url.match(/\/project\/([^/]+)\/flow\/([^/?]+)/);
  if (!match) {
    console.error(`Error: Cannot parse flow URL: ${url}`);
    console.error('Expected: https://app.zeplin.io/project/{project_id}/flow/{flow_board_id}');
    process.exit(1);
  }
  return { projectId: match[1], flowBoardId: match[2] };
}

// ─── Auth ───────────────────────────────────────────────────────────────

function getToken() {
  if (process.env.ZEPLIN_ACCESS_TOKEN) return process.env.ZEPLIN_ACCESS_TOKEN;

  const configPaths = [
    path.join(process.env.HOME || '~', '.config', 'opencode', 'opencode.json'),
    path.join(process.cwd(), 'opencode.json'),
  ];

  for (const cfgPath of configPaths) {
    try {
      const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
      const z = cfg.mcp?.zeplin?.environment?.ZEPLIN_ACCESS_TOKEN;
      if (z) return z;
    } catch {}
  }

  return null;
}

// ─── API Client ─────────────────────────────────────────────────────────

const API_BASE = 'https://api.zeplin.dev/v1';
const API_DELAY_MS = 150; // ~400 req/min headroom under 200 req/min limit

let lastRequestTime = 0;

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function zeplinFetch(endpoint, token) {
  // Rate limiting: ensure minimum delay between requests
  const now = Date.now();
  const elapsed = now - lastRequestTime;
  if (elapsed < API_DELAY_MS) {
    await delay(API_DELAY_MS - elapsed);
  }
  lastRequestTime = Date.now();

  const res = await fetch(`${API_BASE}${endpoint}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });

  // Retry on rate limit (429)
  if (res.status === 429) {
    const retryAfter = parseInt(res.headers.get('retry-after') || '5', 10);
    console.error(`Rate limited on ${endpoint}, waiting ${retryAfter}s...`);
    await delay(retryAfter * 1000);
    lastRequestTime = Date.now();
    return zeplinFetch(endpoint, token);
  }

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Zeplin API ${res.status} ${res.statusText}: ${endpoint}\n${body}`);
  }

  return res.json();
}

// ─── Layer Analysis Heuristics ──────────────────────────────────────────

const INPUT_COMPONENT = /input|textfield|text.field|field|textbox|text.box|select|dropdown|combobox|checkbox|radio|toggle|switch|searchbar|search.bar|date.?picker|time.?picker|number.?input|spinner/i;
const BUTTON_COMPONENT = /button|btn|cta|submit|action|fab/i;
const FIELD_LABEL = /^(email|e-?mail|password|pwd|first.?name|last.?name|name|phone|mobile|address|city|zip|postal|country|state|username|user.?name|confirm|dob|date.?of.?birth|card|number|cvv|cvc|expiry|exp|amount|balance|note|notes|comment|message|title|description|subject|company|organization|org|search|code|otp|pin|ssn|tax|id|url|website|link|amount|price|total|quantity|qty|size|weight|height|width|color|colour|font|style|type|category|status|role|permission|group|tag|label|ref|reference|token|key|secret|otp|pin|code|captcha|sum|result|value|text|content|body|file|image|photo|avatar|attachment|document|path|directory|folder|name)$/i;
const BUTTON_TEXT = /(sign.?in|log.?in|login|submit|save|continue|next|confirm|send|create|add|delete|remove|cancel|back|update|edit|pay|checkout|proceed|apply|accept|reject|approve|deny|skip|close|open|start|stop|pause|resume|retry|reset|clear|search|find|browse|upload|download|share|export|import|subscribe|unsubscribe|follow|unfollow|like|unlike|block|unblock|ban|unban|archive|unarchive|publish|unpublish|draft|preview|review|comment|reply|forward|transfer|assign|delegate|escalate|merge|split|combine|calculate|compute|generate|refresh|reload|sync|connect|disconnect|pair|unpair|link|unlink|enable|disable|activate|deactivate|on|off)/i;
const RESOURCE_FROM_SCREEN = /^(login|sign.?in|register|sign.?up|forgot.?password|reset.?password|verify|confirm|dashboard|home|profile|settings|account|payment|checkout|order|cart|checkout|search|browse|feed|timeline|notifications?|messages?|chat|inbox|sent|drafts?|trash|archive|reports?|analytics|statistics|stats|billing|subscription|pricing|plans?|features?|help|support|faq|docs?|documentation|about|terms|privacy|policy|contact|feedback|invite|team|groups?|members?|roles?|permissions?|admin|panel|panel|moderator|log|audit|history|activity|events?|tasks?|projects?|files?|media|photos?|videos?|documents?|attachments?|links?|bookmarks?|favorites?|saved|pinned|recent|popular|trending|featured|recommended|suggested|all|list|grid|table|calendar|scheduler|timeline|kanban|board|card|detail|view|edit|create|new|add|import|export|upload|download|print|share|embed|embed|api|developer|settings|preferences|config|configuration)$/i;

function analyzeLayers(layers, depth = 0) {
  const result = { inputs: [], buttons: [], labels: [], groups: [] };

  for (const layer of layers || []) {
    const name = layer.name || '';
    const type = layer.type || '';
    const content = layer.content || '';
    const componentName = layer.component_name || '';

    if (type === 'group' && componentName) {
      if (INPUT_COMPONENT.test(componentName)) {
        const childText = findTextInChildren(layer);
        result.inputs.push({
          name, componentName,
          label: childText || extractLabelFromName(name),
          rect: layer.rect,
        });
      } else if (BUTTON_COMPONENT.test(componentName)) {
        const childText = findTextInChildren(layer);
        result.buttons.push({
          name, componentName,
          text: childText || extractLabelFromName(name),
          rect: layer.rect,
        });
      } else {
        result.groups.push({ name, componentName });
      }
    }

    if (type === 'text' && content) {
      if (BUTTON_TEXT.test(content)) {
        result.buttons.push({ name, content, rect: layer.rect });
      } else if (FIELD_LABEL.test(content.toLowerCase()) || content.endsWith(':')) {
        result.labels.push({ name, content: content.replace(/:$/, ''), rect: layer.rect });
      }
    }

    if (layer.layers) {
      const child = analyzeLayers(layer.layers, depth + 1);
      result.inputs.push(...child.inputs);
      result.buttons.push(...child.buttons);
      result.labels.push(...child.labels);
      result.groups.push(...child.groups);
    }
  }

  return result;
}

function findTextInChildren(layer) {
  for (const child of layer.layers || []) {
    if (child.type === 'text' && child.content) return child.content;
    const nested = findTextInChildren(child);
    if (nested) return nested;
  }
  return null;
}

function extractLabelFromName(name) {
  return name
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .trim();
}

// ─── Endpoint Inference ─────────────────────────────────────────────────

// Screens that don't map to API endpoints
const NON_API_SCREEN = /(^|[-_.\s])(intro|onboarding|splash|welcome|empty|loading|placeholder|error|404|500|offline|maintenance|coming.?soon|tutorial|walkthrough|tour|hint|tooltip|popover|banner|notification|toast|snackbar|alert|dialog|modal|popup|overlay|bottom.?sheet|drawer|menu|sidebar|navigation|nav|tab|toolbar|header|footer|hero|feature|benefit|testimonial|cta|marketing|landing|promo|announcement|status)([-_.\s]|$)/i;

// Screen name → resource path mapping (used when layer data is unavailable)
const NAME_TO_RESOURCE = [
  { pattern: /forgot.?password|reset.?password/i, method: 'POST', resource: 'auth/password/reset' },
  { pattern: /login|sign.?in/i, method: 'POST', resource: 'auth/login' },
  { pattern: /register|sign.?up|personal.?info/i, method: 'POST', resource: 'auth/register' },
  { pattern: /verify|verification|mail.?verif/i, method: 'POST', resource: 'auth/verify' },
  { pattern: /dashboard|home/i, method: 'GET', resource: 'dashboard' },
  { pattern: /profile/i, method: 'GET', resource: 'users/me' },
  { pattern: /settings|preferences|account.?settings/i, method: 'GET', resource: 'settings' },
  { pattern: /payment/i, method: 'POST', resource: 'payments' },
  { pattern: /checkout/i, method: 'POST', resource: 'orders' },
  { pattern: /cart/i, method: 'GET', resource: 'cart' },
  { pattern: /order/i, method: 'GET', resource: 'orders' },
  { pattern: /search/i, method: 'GET', resource: 'search' },
  { pattern: /inbox|messages?/i, method: 'GET', resource: 'messages' },
  { pattern: /notifications?/i, method: 'GET', resource: 'notifications' },
  { pattern: /billing/i, method: 'GET', resource: 'billing' },
  { pattern: /subscription|plans?/i, method: 'GET', resource: 'subscriptions' },
  { pattern: /team|members?/i, method: 'GET', resource: 'teams' },
  { pattern: /files?|documents?|attachments?/i, method: 'GET', resource: 'files' },
];

function inferEndpoint(screenName, analysis) {
  const lower = screenName.toLowerCase();

  // Check for non-API screens first
  if (NON_API_SCREEN.test(lower)) {
    return { method: null, resource: null, isNonApi: true };
  }

  let method = 'GET';
  let resource = null;

  // First: try screen name → resource mapping
  for (const mapping of NAME_TO_RESOURCE) {
    if (mapping.pattern.test(lower)) {
      method = mapping.method;
      resource = '/' + mapping.resource;
      break;
    }
  }

  // If no match, derive from screen name
  if (!resource) {
    const words = lower
      .replace(/[0-9]+[a-z]?\b/g, '') // remove version numbers like 1.0a
      .replace(/[-_]/g, ' ')
      .replace(/[^a-z0-9\s]/g, '')
      .split(/\s+/)
      .filter(w => w.length > 2 && !/^(desktop|mobile|web|app|v\d|intro|step|page|screen|modal|popup|dialog|overlay|tab|view|flow)$/i.test(w));
    resource = words[words.length - 1] || 'resource';
  }

  // Refine method from layer analysis (if available)
  const hasInputs = analysis.inputs.length > 0 || analysis.labels.length > 0;
  const hasSubmit = analysis.buttons.some(b => {
    const text = (b.text || b.content || '').toLowerCase();
    return /(submit|create|add|save|send|register|sign.?up|log.?in|sign.?in|confirm|pay|checkout|place|post|publish|apply)/.test(text);
  });
  const hasDelete = analysis.buttons.some(b => {
    const text = (b.text || b.content || '').toLowerCase();
    return /(delete|remove|destroy|purge|trash|bin|archive|drop)/.test(text);
  });
  const hasUpdate = analysis.buttons.some(b => {
    const text = (b.text || b.content || '').toLowerCase();
    return /(update|edit|save|modify|change|patch|put)/.test(text);
  });

  if (hasDelete) {
    method = 'DELETE';
    resource = resource.replace(/s$/, '');
  } else if (hasSubmit && hasInputs) {
    method = 'POST';
  } else if (hasUpdate && hasInputs) {
    method = 'PUT';
  }

  // Normalize: pluralize for POST, singular for DELETE
  if (method === 'POST' && resource && !resource.endsWith('s') && !resource.includes('/')) {
    resource = resource + 's';
  }

  return { method, resource };
}

function inferFields(analysis) {
  const fields = [];

  // Pair labels with inputs heuristically
  const usedLabels = new Set();

  for (const input of analysis.inputs) {
    let fieldLabel = input.label || extractLabelFromName(input.name);
    let type = 'string';
    let required = false;

    const lower = fieldLabel.toLowerCase();
    if (/password|pwd|secret|pin|otp|code/.test(lower)) type = 'password';
    else if (/email|e-?mail/.test(lower)) type = 'email';
    else if (/phone|mobile|tel/.test(lower)) type = 'string'; // phone format
    else if (/amount|price|total|balance|quantity|qty|number|age|width|height|weight/.test(lower)) type = 'number';
    else if (/date|dob|birth|time|expiry|exp/.test(lower)) type = 'string'; // date format
    else if (/checkbox|agree|accept|terms|conditions|tos|remember/.test(lower)) type = 'boolean';

    required = /(password|email|name|phone|amount|token|code|otp|pin|card|cvv|exp)/.test(lower);

    fields.push({ name: toSnakeCase(fieldLabel), type, label: fieldLabel, required });
    usedLabels.add(fieldLabel);
  }

  // Add remaining labels as potential query/body params
  for (const label of analysis.labels) {
    if (!usedLabels.has(label.content)) {
      fields.push({
        name: toSnakeCase(label.content),
        type: 'string',
        label: label.content,
        required: false,
      });
    }
  }

  return fields;
}

function toSnakeCase(str) {
  return str
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, '_')
    .replace(/^_+|_+$/g, '');
}

// ─── Data Fetching ──────────────────────────────────────────────────────

async function fetchFlowData(projectId, flowBoardId, token, includeNotes) {
  const [board, nodes, connectors] = await Promise.all([
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}`, token),
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}/nodes`, token),
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}/connectors`, token),
  ]);

  // Extract screen nodes
  const screenNodes = (nodes || []).filter(n => n.type === 'ScreenNode');

  let layerAvailable = true;

  // Fetch screen details + latest version for each (sequentially for rate limits)
  const screens = [];
  for (const node of screenNodes) {
    const screenId = node.screen?.id;
    if (!screenId) {
      screens.push({ node, screen: null, version: null, notes: [], annotations: [] });
      continue;
    }

    const screen = await zeplinFetch(`/projects/${projectId}/screens/${screenId}`, token);
    const version = await zeplinFetch(
      `/projects/${projectId}/screens/${screenId}/versions/latest`, token
    ).catch(e => {
      if (e.message.includes('403')) layerAvailable = false;
      return null;
    });

    let notes = [];
    let annotations = [];
    if (includeNotes) {
      notes = await zeplinFetch(`/projects/${projectId}/screens/${screenId}/notes`, token)
        .catch(() => []);
      annotations = await zeplinFetch(
        `/projects/${projectId}/screens/${screenId}/annotations`, token
      ).catch(() => []);
    }

    screens.push({ node, screen, version, notes, annotations });
  }

  return { board, nodes: screenNodes, connectors, screens, layerAvailable };
}

// ─── Contract Builder ───────────────────────────────────────────────────

function buildContract(flowData) {
  const { board, connectors, screens } = flowData;

  const nodeIdToScreen = {};
  for (const s of screens) {
    if (s.screen) nodeIdToScreen[s.node.id] = s;
  }

  // Build per-screen analysis
  const endpoints = [];
  const flowEdges = [];

  for (const s of screens) {
    if (!s.screen) continue;

    const layers = s.version?.layers || [];
    const analysis = analyzeLayers(layers);
    const endpoint = inferEndpoint(s.screen.name, analysis);
    const fields = inferFields(analysis);

    const screenAnnotations = (s.annotations || [])
      .map(a => a.content)
      .filter(Boolean);
    const screenNotes = (s.notes || [])
      .flatMap(n => (n.comments || []).map(c => c.content))
      .filter(Boolean);

    // Check annotations for explicit API hints
    const allHints = [...screenAnnotations, ...screenNotes];
    const apiHint = allHints.find(h =>
      /(POST|GET|PUT|PATCH|DELETE)\s+\/|\/api\//i.test(h)
    );

    endpoints.push({
      screen: s.screen.name,
      screenId: s.screen.id,
      nodeId: s.node.id,
      method: endpoint.method,
      path: apiHint ? extractPathFromHint(apiHint) : endpoint.resource,
      isNonApi: endpoint.isNonApi || false,
      fields,
      buttons: analysis.buttons.map(b => b.text || b.content || ''),
      inputCount: analysis.inputs.length,
      notes: allHints,
    });
  }

  // Build flow edges from connectors
  for (const c of connectors || []) {
    const from = nodeIdToScreen[c.start?.node?.id]?.screen?.name || c.start?.node?.id;
    const to = nodeIdToScreen[c.end?.node?.id]?.screen?.name || c.end?.node?.id;
    const label = c.end?.label?.text || c.label?.text || '';

    flowEdges.push({ from, to, label, type: c.type });
  }

  return {
    flowBoard: {
      id: board.id,
      name: board.name || 'Unnamed Flow',
      description: board.description || '',
      projectId: flowData.board.project || '',
    },
    endpoints,
    flow: flowEdges,
    screenCount: screens.length,
    connectorCount: (connectors || []).length,
    layerAvailable: flowData.layerAvailable,
  };
}

function extractPathFromHint(text) {
  const match = text.match(/(GET|POST|PUT|PATCH|DELETE)\s+(\/[^\s,;]+)/i);
  if (match) return match[2];
  const pathMatch = text.match(/(\/api\/[^\s,;]+)/i);
  if (pathMatch) return pathMatch[1];
  return null;
}

// ─── Output Formatters ──────────────────────────────────────────────────

function outputMarkdown(contract) {
  const lines = [];
  const { flowBoard, endpoints, flow, screenCount, connectorCount, layerAvailable } = contract;

  lines.push(`# API Contract: ${flowBoard.name}\n`);
  lines.push(`**Flow:** ${flowBoard.name}`);
  lines.push(`**Screens:** ${screenCount} | **Connectors:** ${connectorCount}`);
  lines.push(`**Generated:** ${new Date().toISOString()}`);

  if (!layerAvailable) {
    lines.push('\n> **Note:** Layer data unavailable (403 Forbidden). Endpoint inference is based on screen names and flow structure only. For full layer analysis, ensure the API token has editor access to the project.');
  }
  lines.push('');

  // Screens summary — API screens
  const apiEndpoints = endpoints.filter(e => !e.isNonApi);
  const nonApiScreens = endpoints.filter(e => e.isNonApi);

  if (apiEndpoints.length > 0) {
    lines.push('## API Screens\n');
    lines.push('| Screen | Method | Path | Inputs | Buttons |');
    lines.push('|--------|--------|------|--------|---------|');
    for (const ep of apiEndpoints) {
      const btns = ep.buttons.length > 0 ? ep.buttons.join(', ') : '-';
      lines.push(`| ${ep.screen} | ${ep.method} | \`${ep.path}\` | ${ep.inputCount} | ${btns} |`);
    }
  }

  if (nonApiScreens.length > 0) {
    lines.push('\n## Non-API Screens (onboarding, intro, etc.)\n');
    for (const ep of nonApiScreens) {
      lines.push(`- ${ep.screen}`);
    }
  }

  // Flow diagram
  if (flow.length > 0) {
    lines.push('\n## Flow\n');
    for (const edge of flow) {
      const label = edge.label ? ` -- "${edge.label}"` : '';
      lines.push(`[${edge.from}]${label} --> [${edge.to}]`);
    }
  }

  // Detailed endpoints (only API screens)
  if (apiEndpoints.length > 0) {
    lines.push('\n## Endpoints\n');
    for (const ep of apiEndpoints) {
      lines.push(`### ${ep.method} \`${ep.path}\``);
      lines.push(`- **Screen:** ${ep.screen}`);

      if (ep.fields.length > 0) {
        lines.push('- **Fields:**');
        for (const f of ep.fields) {
          const req = f.required ? ', required' : ', optional';
          lines.push(`  - \`${f.name}\` (${f.type}${req}) — "${f.label}"`);
        }
      } else {
        lines.push('- **Fields:** none detected (layer data unavailable)');
      }

      if (ep.notes.length > 0) {
        lines.push('- **Developer notes:**');
        for (const n of ep.notes) {
          lines.push(`  - ${n}`);
        }
      }

      lines.push('');
    }
  }

  return lines.join('\n');
}

// ─── Main ───────────────────────────────────────────────────────────────

async function main() {
  const token = getToken();
  if (!token) {
    console.error(
      'Error: No ZEPLIN_ACCESS_TOKEN found.\n' +
      'Set ZEPLIN_ACCESS_TOKEN env var or configure zeplin MCP server in opencode.json.'
    );
    process.exit(1);
  }

  const { projectId, flowBoardId } = parseFlowUrl(flowUrl);

  const flowData = await fetchFlowData(projectId, flowBoardId, token, includeNotes);
  const contract = buildContract(flowData);

  if (outputJson) {
    console.log(JSON.stringify(contract, null, 2));
  } else {
    console.log(outputMarkdown(contract));
  }
}

main().catch(err => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
