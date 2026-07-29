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
const API_DELAY_MS = 150;

let lastRequestTime = 0;

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function zeplinFetch(endpoint, token) {
  const now = Date.now();
  const elapsed = now - lastRequestTime;
  if (elapsed < API_DELAY_MS) await delay(API_DELAY_MS - elapsed);
  lastRequestTime = Date.now();

  const res = await fetch(`${API_BASE}${endpoint}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });

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

// Strict field label patterns — only these are considered real API fields
const FIELD_LABEL = /^(email|e-?mail|password|pwd|confirm.?password|new.?password|first.?name|last.?name|name|phone|mobile|address|city|zip|postal|country|state|username|user.?name|dob|date.?of.?birth|card.?number|cvv|cvc|expiry|exp.?date|amount|balance|note|notes|comment|message|title|description|subject|company|organization|org|search|code|otp|pin|ssn|tax.?id|url|website|link|price|total|quantity|qty|size|weight|height|width|color|colour|font|style|type|category|status|role|permission|group|tag|label|ref|reference|token|key|secret|captcha|sum|result|value|text|content|body|path|directory|folder)$/i;

// Button text that indicates form submission
const SUBMIT_BUTTON = /(sign.?in|log.?in|login|submit|save|continue|next|confirm|send|create|add|pay|checkout|proceed|apply|accept|register|sign.?up|reset|verify)/i;

// ─── Noise Filters ──────────────────────────────────────────────────────

// Text that looks like placeholder/example content
const PLACEHOLDER_TEXT = /^(e\.g\.|eg\.|for example|example|such as|placeholder|insert|enter|type|input|write|please)/i;
const EXAMPLE_VALUE = /^[\w.+-]+@[\w.-]+\.\w+$|^\d{3}\s?\d{3}|^\*{3,}|^[x]{3,}|^#{3,}/;
const PASSWORD_MASK = /^[*x#]{3,}$/;

// Navigation, filter, and UI chrome text
const NAVIGATION_TEXT = /^(back|close|menu|home|profile|settings|inspirations|orders.*transactions|dashboard|help|support|faq|about|contact|legal|privacy|terms|logout|log.?out|sign.?out|switch|change|manage|view.?all|see.?all|show.?more|load.?more|scroll|swipe|tap|click|press|hold|drag|drop|zoom|pinch|rotate|shake|tilt)$/i;
const FILTER_TEXT = /^(filter|search|sort|order|group|view|display|show|hide|toggle|expand|collapse|open|close|reset|clear|apply|cancel|done|ok|yes|no|true|false|all|none|select|deselect|check|uncheck)$/i;
const STATUS_TEXT = /^(active|inactive|enabled|disabled|online|offline|pending|processing|completed|failed|error|success|warning|info|draft|published|archived|deleted|expired|expiring|suspended|blocked|verified|unverified|confirmed|cancelled|refunded|paid|unpaid|overdue|due)$/i;
const PERIOD_TEXT = /^(today|yesterday|tomorrow|this.?week|last.?week|next.?week|this.?month|last.?month|next.?month|this.?year|last.?year|next.?year|past.?week|past.?month|past.?6.?month|past.?year|last.?30.?days|last.?90.?days|all.?time|custom|date.?range)$/i;
const UI_CHROME = /^(navbutton|paginator|checkbox.?outline|radio.?button|icon.?button|insert.*tooltip|tab|tab.?bar|header|footer|sidebar|drawer|modal|dialog|popup|overlay|bottom.?sheet|toast|snackbar|banner|alert|notification|chip|badge|avatar|icon|image|logo|divider|separator|spacer|loading|spinner|skeleton|placeholder|empty.?state|no.?data|no.?results|error.?state|success.?state|info.?state|warning.?state)$/i;
const RESOURCE_NAME = /^(tool|tools|flex|license|licence|licenses|software|obd|ecm|ixi|dyno|magservice|flasher|line|pro|personal|professional|enterprise|basic|free|premium|plus|gold|silver|bronze|standard|advanced|lite|mini|micro|nano|ultra|super|mega|giga|tera|peta|exa|zetta|yotta|bench|master|slave)$/i;
const GENERIC_LABEL = /^(title|name|label|text|description|content|value|data|info|information|details|summary|note|notes|comment|comments|message|messages|body|footer|header|sidebar|main|content|primary|secondary|tertiary|accent|highlight|emphasis|bold|italic|underline|strikethrough|code|pre|blockquote|list|item|element|component|widget|module|section|block|chunk|segment|part|piece|bit|byte|word|character|letter|digit|number|symbol|icon|image|picture|photo|video|audio|file|document|link|url|href|src|alt|title|text|select.?filter|filter.?title|licence.?status|activities|dynomag|ixi.?personal|ixi.?professional|oem|tabitem|tabelementtext|boot|bench|tab|tabitem|tabelement)$/i;

function isNoiseText(content) {
  if (!content || content.length < 2) return true;
  const trimmed = content.trim();

  if (PASSWORD_MASK.test(trimmed)) return true;
  if (PLACEHOLDER_TEXT.test(trimmed)) return true;
  if (EXAMPLE_VALUE.test(trimmed)) return true;
  if (NAVIGATION_TEXT.test(trimmed)) return true;
  if (FILTER_TEXT.test(trimmed)) return true;
  if (STATUS_TEXT.test(trimmed)) return true;
  if (PERIOD_TEXT.test(trimmed)) return true;
  if (UI_CHROME.test(trimmed)) return true;
  if (RESOURCE_NAME.test(trimmed)) return true;
  if (GENERIC_LABEL.test(trimmed)) return true;

  // Filter options with parentheses like "Filter (3)"
  if (/^\w+\s*\(\d+\)$/.test(trimmed)) return true;

  // Single word + number like "Filter 3"
  if (/^\w+\s+\d+$/.test(trimmed)) return true;

  // Material icon names (kebab-case or camelCase with icon keywords)
  const MATERIAL_ICON = /^(check|close|search|filter|sort|menu|arrow|chevron|expand|collapse|add|remove|edit|delete|save|undo|redo|refresh|sync|settings|info|warning|error|success|help|home|person|group|lock|unlock|visibility|visibility-off|star|favorite|share|link|attach|upload|download|send|print|copy|cut|paste|forward|backward|first|last|play|pause|stop|volume|mic|camera|photo|image|video|chat|comment|mail|phone|location|map|calendar|clock|alarm|timer|tag|label|bookmark|flag|pin|thumb|like|heart|smile|frown|neutral|alert|notice|bell|notification|badge|shield|key|lock|globe|wifi|bluetooth|battery|signal|power|plug|usb|sd|card|folder|file|document|cloud|server|database|code|terminal|bug|wrench|tool|hammer|screwdriver|gear|cog|sliders|toggle|switch|checkbox|radiobutton|check|uncheck|select|deselect|mark|tick|cross|x|done|ok|cancel|approve|reject|accept|decline|yes|no)$/i;

  // Material icon pattern (contains "icon" or is a known icon name)
  if (MATERIAL_ICON.test(trimmed.replace(/[-_]/g, '').toLowerCase())) return true;

  // Hyphenated icon/component names
  if (/^(icon[-_]|material[-_]|md[-_]|nav[-_]|tab[-_]|btn[-_]|button[-_]|input[-_]|field[-_]|checkbox[-_]|radio[-_]|toggle[-_]|switch[-_]|select[-_]|dropdown[-_]|search[-_]|filter[-_]|sort[-_]|menu[-_])/i.test(trimmed)) return true;

  // Looks like a component/icon identifier (lowercase, no spaces, often hyphenated or camelCase)
  if (/^[a-z]+[-_][a-z]+[-_]?[a-z]*$/.test(trimmed) && !/^(email|password|first_name|last_name|phone|address|city|zip|country|state|username|confirm)/.test(trimmed)) return true;

  // Concatenated lowercase words (breadcrumb, elementsection, tileclassic, etc.)
  if (/^[a-z]{8,}$/.test(trimmed) && !/^(password|username|email|address|country|city|phone|number|total|amount|serial|credit|card|expir|cvv|cardholder|postcode|street)/.test(trimmed)) return true;

  // Tile/component names (tile/classic, tileclassic, tilewide, tilesmall, etc.)
  if (/^tile[\/_]?(classic|wide|small|medium|large|square|rectangular|horizontal|vertical|compact|expanded|collapsed|active|inactive|selected|deselected|enabled|disabled)$/i.test(trimmed)) return true;

  // Country options with underscores (united_kingdom_uk, etc.)
  if (/^(united_kingdom|united_states|united_kingdom_uk|united_states_usa|new_zealand|south_africa|south_korea|saudi_arabia|united_arab|costa_rica|dominican|el_salvador|puerto_rico|trinidad_tobago|san_marino)$/i.test(trimmed)) return true;

  // Country names as labels (Italy, United Kingdom, etc.) — with optional parenthetical
  if (/^(italy|united kingdom|uk|usa|united states|canada|australia|germany|france|spain|portugal|netherlands|belgium|switzerland|austria|ireland|sweden|norway|denmark|finland|poland|czech|slovakia|hungary|romania|bulgaria|greece|croatia|slovenia|estonia|latvia|lithuania|luxembourg|malta|cyprus|monaco|liechtenstein|iceland|andorra|san marino|vatican|south africa|brazil|mexico|argentina|chile|colombia|peru|china|japan|korea|india|singapore|hong kong|taiwan|thailand|vietnam|philippines|malaysia|indonesia|new zealand|england|scotland|wales)(\s*\([^)]+\))?$/i.test(trimmed)) return true;

  // Breadcrumb/navigation component names (including slash versions)
  if (/^(breadcrumb|elementsection|navigationsection|headersection|footersection|sidebarsection|menusection|tabsection|toolbarsection|navsection|contentsection|mainsection|primarysection|secondarysection|breadcrumbelementsection|navigationelementsection|headerelementsection|footerelementsection|sidebarelementsection|menuelementsection|tabelementsection|toolbarelementsection|navelementsection|contentelementsection|mainelementsection|primaryelementsection|secondaryelementsection|breadcrumb\/element-section|navigation\/element-section|header\/element-section|footer\/element-section|sidebar\/element-section|menu\/element-section|tab\/element-section|toolbar\/element-section|nav\/element-section|content\/element-section|main\/element-section|primary\/element-section|secondary\/element-section)$/i.test(trimmed)) return true;

  // Very short (likely icon/chrome text)
  if (trimmed.length <= 2) return true;

  // Contains ellipsis (search hint)
  if (/\.\.\./.test(trimmed)) return true;

  // Looks like a date/time format
  if (/^\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}/.test(trimmed)) return true;

  // Looks like a number-only text
  if (/^\d+$/.test(trimmed)) return true;

  // Contains underscores (likely component name, not user-facing text)
  if (/^[\w]+_[\w]+/.test(trimmed) && !/^(email|password|first_name|last_name|confirm_password|new_password|credit_card|cardholder_name|credit_card_number|expiration_date|serial_number|licence_status|filters_title)/.test(trimmed)) return true;

  // Example names (first + last, or just a name)
  if (/^[A-Z][a-z]+\s[A-Z][a-z]+$/.test(trimmed) && !/^(First Name|Last Name|Cardholder Name|Full Name)$/.test(trimmed)) return true;

  // Single-word example names (common in placeholder text)
  if (/^(mario|rossi|giovanni|esposito|luca|marco|andrea|alessandro|simone|davide|luigi|antonio|francesca|giulia|maria|sara|giorgia|chiara|valentina|federica|elena|roberto|paolo|giovanni|luigi|francesco|giuseppe|carlo|alessio|matteo|riccardo|emanuele|filippo|daniele|stefano|alessandra|valeria|martina|laura|anna|elisa|beatrice|silvia|piera|carmela|rosa|maria)$/i.test(trimmed)) return true;

  // Example street addresses (Italian style: Via + name + number)
  if (/^(via|strada|corso|piazza|viale|lungomare|piazzale|vicolo|traversa|borgo)\s/i.test(trimmed)) return true;

  // Example city names (Italian and English)
  if (/^(roma|milano|napoli|torino|palermo|genova|bologna|firenze|bari|catania|venezia|verona|messina|padova|trieste|brescia|parma|modena|reggio|perugia|cagliari|sassari|anzio|osti|fiumicino|ciampino|london|manchester|birmingham|leeds|glasgow|edinburgh|liverpool|bristol|cardiff|belfast|oxford|cambridge|brighton|bath|york|chester|canterbury|warwick|stratford|windsor|oxford)$/i.test(trimmed)) return true;

  // Country/region options (common in shipping forms)
  if (/^(italy|united.?kingdom|uk|usa|united.?states|canada|austr germany|france|spain|portugal|netherlands|belgium|switzerland|austria|ireland|sweden|norway|denmark|finland|poland|czech|slovakia|hungary|romania|bulgaria|greece|croatia|slovenia|estonia|latvia|lithuania|luxembourg|malta|cyprus|monaco|liechtenstein|iceland|andorra|san.?marino|vatican|south.?africa|brazil|mexico|argentina|chile|colombia|peru|china|japan|korea|india|singapore|hong.?kong|taiwan|thailand|vietnam|philippines|malaysia|indonesia|new.?zealand)$/i.test(trimmed)) return true;

  // Navigation items
  if (/^(buy.?new.?service|my.?services|services|dashboard|home|profile|settings|account|billing|payments|orders|invoices|reports|analytics|admin|support|help|docs|documentation|faq|contact|about|blog|careers|press|legal|privacy|terms|cookies|security|status|sitemap)$/i.test(trimmed)) return true;

  // Example VIN/serial patterns (17-char alphanumeric, common in automotive)
  if (/^[A-Z0-9]{10,20}$/i.test(trimmed)) return true;

  // Country code prefixes (+39, +44, +1, etc.)
  if (/^\+\d{1,4}$/.test(trimmed)) return true;

  // Example postal codes (UK, Italian, etc.)
  if (/^[A-Z]{1,2}\d{1,2}[A-Z]?\s?\d[A-Z]{2}$/i.test(trimmed)) return true; // UK
  if (/^\d{5}$/.test(trimmed)) return true; // Italian
  if (/^\d{5}-\d{4}$/.test(trimmed)) return true; // US

  // Hex strings (example serial/hash)
  if (/^[0-9a-f]{8,}$/i.test(trimmed)) return true;

  // Looks like a date format (MM/DD, DD/MM, MM/YY, DD.MM.YYYY, etc.)
  if (/^\d{2}[\/.-]\d{2}([\/.-]\d{2,4})?$/.test(trimmed)) return true;

  // Long text (> 30 chars) — likely help text, error message, or description
  if (trimmed.length > 30) return true;

  // Sentences (contains period followed by space)
  if (/\.\s/.test(trimmed)) return true;

  // Payment method options
  if (/^(paypal|bank.?transfer|credit.?card|debit.?card|wire.?transfer|crypto|bitcoin|apple.?pay|google.?pay|samsung.?pay|venmo|zelle|cashapp|afterpay|klarna|affirm)$/i.test(trimmed)) return true;

  // Tab/navigation elements
  if (/^(tab\/|nav\/|menu\/|sidebar\/|header\/|footer\/|toolbar\/|tabbar)/i.test(trimmed)) return true;

  // Boot, system, and other technical terms
  if (/^(boot|shutdown|restart|reboot|reset|power|sleep|wake|suspend|resume|hibernate)$/i.test(trimmed)) return true;

  return false;
}

// ─── Layer Analysis ─────────────────────────────────────────────────────

function analyzeLayers(layers) {
  const result = { inputs: [], buttons: [], labels: [] };

  for (const layer of layers || []) {
    const name = layer.name || '';
    const type = layer.type || '';
    const content = layer.content || '';
    const componentName = layer.component_name || '';

    if (type === 'group' && componentName) {
      if (INPUT_COMPONENT.test(componentName)) {
        const childText = findTextInChildren(layer);
        const label = childText || name;
        if (!isNoiseText(label)) {
          result.inputs.push({ name, label, rect: layer.rect });
        }
      } else if (BUTTON_COMPONENT.test(componentName)) {
        const childText = findTextInChildren(layer);
        const text = childText || name;
        if (!isNoiseText(text)) {
          result.buttons.push({ name, text, rect: layer.rect });
        }
      }
    }

    if (type === 'text' && content && !isNoiseText(content)) {
      const lower = content.toLowerCase();
      if (SUBMIT_BUTTON.test(content)) {
        result.buttons.push({ name, text: content, rect: layer.rect });
      } else if (FIELD_LABEL.test(lower) || content.endsWith(':')) {
        const label = content.replace(/:$/, '');
        result.labels.push({ name, content: label, rect: layer.rect });
      }
    }

    if (layer.layers) {
      const child = analyzeLayers(layer.layers);
      result.inputs.push(...child.inputs);
      result.buttons.push(...child.buttons);
      result.labels.push(...child.labels);
    }
  }

  return result;
}

function findTextInChildren(layer) {
  for (const child of layer.layers || []) {
    if (child.type === 'text' && child.content && !isNoiseText(child.content)) {
      return child.content;
    }
    const nested = findTextInChildren(child);
    if (nested) return nested;
  }
  return null;
}

// ─── Endpoint Inference ─────────────────────────────────────────────────

const NON_API_SCREEN = /(^|[-_.\s])(intro|onboarding|splash|welcome|empty|loading|placeholder|error|404|500|offline|maintenance|coming.?soon|tutorial|walkthrough|tour|hint|tooltip|popover|banner|notification|toast|snackbar|alert|dialog|modal|popup|overlay|bottom.?sheet|drawer|menu|sidebar|navigation|nav|tab|toolbar|header|footer|hero|feature|benefit|testimonial|cta|marketing|landing|promo|announcement|status)([-_.\s]|$)/i;

const NAME_TO_ENDPOINT = [
  { pattern: /forgot.?password|reset.?password/i, method: 'POST', path: '/auth/password/reset' },
  { pattern: /login|sign.?in/i, method: 'POST', path: '/auth/login' },
  { pattern: /register|sign.?up|personal.?info/i, method: 'POST', path: '/auth/register' },
  { pattern: /verify|verification|mail.?verif/i, method: 'POST', path: '/auth/verify' },
  { pattern: /forgot.*otp|otp.*verify/i, method: 'POST', path: '/auth/otp/verify' },
  { pattern: /dashboard|home/i, method: 'GET', path: '/dashboard' },
  { pattern: /profile|account/i, method: 'GET', path: '/users/me' },
  { pattern: /settings|preferences/i, method: 'GET', path: '/settings' },
  { pattern: /payment/i, method: 'POST', path: '/payments' },
  { pattern: /checkout/i, method: 'POST', path: '/orders' },
  { pattern: /cart/i, method: 'GET', path: '/cart' },
  { pattern: /order/i, method: 'GET', path: '/orders' },
  { pattern: /search/i, method: 'GET', path: '/search' },
  { pattern: /inbox|messages?/i, method: 'GET', path: '/messages' },
  { pattern: /notifications?/i, method: 'GET', path: '/notifications' },
  { pattern: /billing/i, method: 'GET', path: '/billing' },
  { pattern: /subscription|plans?/i, method: 'GET', path: '/subscriptions' },
  { pattern: /team|members?/i, method: 'GET', path: '/teams' },
  { pattern: /files?|documents?|attachments?/i, method: 'GET', path: '/files' },
  { pattern: /renew.*license|license.*renew/i, method: 'POST', path: '/licenses/renew' },
  { pattern: /license|licence/i, method: 'GET', path: '/licenses' },
  { pattern: /tool/i, method: 'GET', path: '/tools' },
];

function inferEndpoint(screenName, analysis) {
  const lower = screenName.toLowerCase();

  if (NON_API_SCREEN.test(lower)) {
    return { method: null, resource: null, isNonApi: true };
  }

  let method = 'GET';
  let path = null;

  for (const mapping of NAME_TO_ENDPOINT) {
    if (mapping.pattern.test(lower)) {
      method = mapping.method;
      path = mapping.path;
      break;
    }
  }

  if (!path) {
    path = '/' + extractResourceFromName(screenName);
  }

  // Refine method from layer analysis
  const hasSubmit = analysis.buttons.some(b => SUBMIT_BUTTON.test(b.text));
  const hasDelete = analysis.buttons.some(b =>
    /(delete|remove|destroy|purge|trash|bin|archive|drop)/i.test(b.text)
  );

  if (hasDelete) method = 'DELETE';
  else if (hasSubmit && analysis.inputs.length > 0) method = 'POST';

  // Pluralize resource for GET (list) endpoints
  if (method === 'GET' && path && !path.endsWith('s') && !path.includes('/') && !path.endsWith('/me')) {
    path = path + 's';
  }

  return { method, resource: path };
}

// ─── Resource Extraction ────────────────────────────────────────────────

function extractResourceFromName(screenName) {
  let name = screenName.toLowerCase();

  // Strip version prefix ("1.0a_", "1.0.2.2a_", "0.0a_")
  name = name.replace(/^[0-9]+(\.[0-9a-z]+)*_/, '');

  // Strip level qualifiers and device suffixes
  name = name.replace(/-(first|second|third|fourth|fifth|sixth)-level/, '');
  name = name.replace(/-(desktop|mobile|web|tablet|app)$/, '');

  // Check for compound keywords (multi-word resources)
  if (/renew.*(license|licence)/i.test(name)) return 'licenses';
  if (/forgot.*password|reset.*password/i.test(name)) return 'password';
  if (/verification.*code|verify/i.test(name)) return 'verify';
  if (/login.*sign|sign.*in/i.test(name)) return 'login';
  if (/register|sign.*up|personal.*info/i.test(name)) return 'register';
  if (/forgot.*otp|otp.*verify/i.test(name)) return 'otp';
  if (/data.*review/i.test(name)) return 'data-review';
  if (/payment|checkout|pay/i.test(name)) return 'payments';
  if (/license|licence/i.test(name)) return 'license';
  if (/tool/i.test(name)) return 'tool';
  if (/flex/i.test(name)) return 'flex';
  if (/ecm/i.test(name)) return 'ecm';
  if (/obd/i.test(name)) return 'obd';
  if (/software/i.test(name)) return 'software';
  if (/dashboard|home/i.test(name)) return 'dashboard';
  if (/setting|account/i.test(name)) return 'settings';

  // Remove leading "my-" prefix
  name = name.replace(/^my-/, '');

  // Find the most meaningful word
  const parts = name.split(/[-_\s]+/).filter(w =>
    w.length > 2 && !/^(first|second|third|fourth|level|page|screen|step|view|tab|form|main|desktop|mobile|web|tablet)$/i.test(w)
  );

  if (parts.length === 0) return 'resource';
  if (parts.length === 1) return parts[0];
  return parts[parts.length - 1];
}

// ─── Field Inference ────────────────────────────────────────────────────

function inferFields(analysis) {
  const fields = [];
  const usedLabels = new Set();

  for (const input of analysis.inputs) {
    const fieldLabel = input.label;
    const lower = fieldLabel.toLowerCase();

    // Skip noise in inputs too
    if (isNoiseText(fieldLabel)) continue;

    let type = 'string';
    let required = false;

    if (/password|pwd|secret|pin|otp|code/.test(lower)) type = 'password';
    else if (/email|e-?mail/.test(lower)) type = 'email';
    else if (/phone|mobile|tel/.test(lower)) type = 'string';
    else if (/amount|price|total|balance|quantity|qty|number|age|width|height|weight/.test(lower)) type = 'number';
    else if (/date|dob|birth|time|expiry|exp/.test(lower)) type = 'string';
    else if (/checkbox|agree|accept|terms|conditions|tos|remember/.test(lower)) type = 'boolean';

    required = /(password|email|name|phone|amount|token|code|otp|pin|card|cvv|exp)/.test(lower);

    fields.push({ name: toSnakeCase(fieldLabel), type, label: fieldLabel, required });
    usedLabels.add(fieldLabel);
  }

  for (const label of analysis.labels) {
    if (!usedLabels.has(label.content) && !isNoiseText(label.content)) {
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

// ─── Resource Grouping ──────────────────────────────────────────────────

function deduplicateFields(fields) {
  const seen = new Map();
  for (const f of fields) {
    const key = `${f.name}_${f.type}`;
    const existing = seen.get(key);
    if (!existing) {
      seen.set(key, f);
    } else if (f.required && !existing.required) {
      seen.set(key, f);
    }
  }
  return [...seen.values()];
}

function groupResources(endpoints) {
  const groups = new Map();

  for (const ep of endpoints) {
    if (ep.isNonApi) continue;
    const key = `${ep.method}_${ep.path}`;
    if (!groups.has(key)) {
      groups.set(key, { method: ep.method, path: ep.path, screens: [] });
    }
    groups.get(key).screens.push(ep);
  }

  return [...groups.values()].map(group => {
    const allFields = group.screens.flatMap(s => s.fields);
    const merged = deduplicateFields(allFields);

    const variantFields = group.screens.map(s => ({
      screen: s.screen,
      fields: s.fields,
      buttons: s.buttons.filter(b => !/[a-z]{2,20}\s[a-z]{2,20}\s[a-z]{2,20}/i.test(b)),
    }));

    return {
      method: group.method,
      path: group.path,
      screenCount: group.screens.length,
      mergedFields: merged,
      variants: variantFields,
      jsonExample: generateJsonExample(merged),
    };
  });
}

function generateJsonExample(fields) {
  const example = {};
  for (const f of fields) {
    switch (f.type) {
      case 'number': example[f.name] = 0; break;
      case 'boolean': example[f.name] = false; break;
      case 'password': example[f.name] = '********'; break;
      case 'email': example[f.name] = 'user@example.com'; break;
      default: example[f.name] = '';
    }
  }
  return example;
}

// ─── Data Fetching ──────────────────────────────────────────────────────

async function fetchFlowData(projectId, flowBoardId, token, includeNotes) {
  const [board, nodes, connectors] = await Promise.all([
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}`, token),
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}/nodes`, token),
    zeplinFetch(`/projects/${projectId}/flow_boards/${flowBoardId}/connectors`, token),
  ]);

  const screenNodes = (nodes || []).filter(n => n.type === 'ScreenNode');
  let layerAvailable = true;

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

  const endpoints = [];
  const flowEdges = [];

  for (const s of screens) {
    if (!s.screen) continue;

    const layers = s.version?.layers || [];
    const analysis = analyzeLayers(layers);
    const endpoint = inferEndpoint(s.screen.name, analysis);
    const fields = inferFields(analysis);

    const screenAnnotations = (s.annotations || []).map(a => a.content).filter(Boolean);
    const screenNotes = (s.notes || []).flatMap(n => (n.comments || []).map(c => c.content)).filter(Boolean);
    const allHints = [...screenAnnotations, ...screenNotes];
    const apiHint = allHints.find(h => /(POST|GET|PUT|PATCH|DELETE)\s+\/|\/api\//i.test(h));

    endpoints.push({
      screen: s.screen.name,
      screenId: s.screen.id,
      nodeId: s.node.id,
      method: endpoint.method,
      path: apiHint ? extractPathFromHint(apiHint) : endpoint.resource,
      isNonApi: endpoint.isNonApi || false,
      fields,
      buttons: analysis.buttons.map(b => b.text || '').filter(b => !isNoiseText(b)),
      inputCount: analysis.inputs.length,
      notes: allHints,
    });
  }

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
    resources: groupResources(endpoints),
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
  const { flowBoard, endpoints, resources, flow, screenCount, connectorCount, layerAvailable } = contract;

  lines.push(`# API Contract: ${flowBoard.name}\n`);
  lines.push(`**Flow:** ${flowBoard.name}`);
  lines.push(`**Screens:** ${screenCount} | **Connectors:** ${connectorCount}`);
  lines.push(`**Generated:** ${new Date().toISOString()}`);

  if (!layerAvailable) {
    lines.push('\n> **Note:** Layer data unavailable (403 Forbidden). Endpoint inference is based on screen names only. For field-level analysis, ensure the API token has editor access to the project.');
  }
  lines.push('');

  // Overview
  const apiEndpoints = endpoints.filter(e => !e.isNonApi);
  const nonApiScreens = endpoints.filter(e => e.isNonApi);

  lines.push('## Overview\n');
  lines.push('| Metric | Count |');
  lines.push('|--------|-------|');
  lines.push(`| API Screens | ${apiEndpoints.length} |`);
  lines.push(`| Non-API Screens | ${nonApiScreens.length} |`);
  lines.push(`| Endpoints | ${resources.length} |`);

  if (flow.length > 0) {
    const validFlow = flow.filter(e => !/^[a-f0-9]{24}$/.test(e.from) || !/^[a-f0-9]{24}$/.test(e.to));
    if (validFlow.length > 0) {
      lines.push(`\n**Flow path:**\n`);
      for (const edge of validFlow) {
        const label = edge.label ? ` -- "${edge.label}"` : '';
        lines.push(`  \`${edge.from}\`${label} → \`${edge.to}\``);
      }
    }
  }
  lines.push('');

  // Endpoints
  if (resources.length > 0) {
    lines.push('## Endpoints\n');

    for (const res of resources) {
      lines.push(`### ${res.method} \`${res.path}\``);
      lines.push(`**Screens:** ${res.screenCount} variant(s)\n`);

      if (res.mergedFields.length > 0) {
        lines.push('| Field | Type | Required | Label |');
        lines.push('|-------|------|----------|-------|');
        for (const f of res.mergedFields) {
          lines.push(`| \`${f.name}\` | ${f.type} | ${f.required ? 'yes' : 'no'} | ${f.label} |`);
        }
        lines.push('');

        lines.push('```json');
        lines.push(JSON.stringify(res.jsonExample, null, 2));
        lines.push('```\n');
      } else {
        lines.push('> No fields detected.\n');
      }

      if (res.variants.length > 0) {
        const hasExtraFields = res.variants.some(v =>
          v.fields.some(f => !res.mergedFields.some(mf => mf.name === f.name))
        );

        if (hasExtraFields) {
          lines.push('**Variant-specific fields:**\n');
          lines.push('| Screen | Fields | Buttons |');
          lines.push('|--------|--------|---------|');
          for (const v of res.variants) {
            const extra = v.fields
              .filter(f => !res.mergedFields.some(mf => mf.name === f.name))
              .map(f => f.label)
              .join(', ');
            const btns = v.buttons.filter(Boolean).join(', ');
            const name = v.screen.replace(/-desktop$/, '').replace(/^[0-9.]+[a-z]?_/, '');
            lines.push(`| ${name} | ${extra || '—'} | ${btns || '—'} |`);
          }
          lines.push('');
        }
      }
    }
  }

  if (nonApiScreens.length > 0) {
    lines.push('## Non-API Screens\n');
    for (const ep of nonApiScreens) {
      const name = ep.screen.replace(/-desktop$/, '');
      lines.push(`- ${name}`);
    }
    lines.push('');
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
