'use strict';

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const dns = require('dns/promises');
const net = require('net');
const { Readable, Transform } = require('stream');
const { pipeline } = require('stream/promises');

const PORT = Number(process.env.PORT || 8080);
// Bind to loopback by default: the CORS proxy is a dev convenience, not a
// service that should be reachable from the rest of the network.
const HOST = process.env.HOST || '127.0.0.1';
const WEB_DIR = path.resolve(__dirname, 'build', 'web');

const MAX_REDIRECTS = 5;
// Abort stalled connections, but never impose a total duration on large video
// downloads. The timer is refreshed whenever another body chunk arrives.
const PROXY_IDLE_TIMEOUT_MS = 30000;
const MAX_REQUEST_BODY_BYTES = Number(process.env.MAX_REQUEST_BODY_BYTES || 1024 * 1024);
const RATE_LIMIT_WINDOW_MS = 60000;
const RATE_LIMIT_MAX = Number(process.env.RATE_LIMIT_MAX || 120);
const rateBuckets = new Map();
const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.mp3': 'audio/mpeg',
  '.m4a': 'audio/mp4',
};

// ---------------------------------------------------------------------------
// SSRF protection
// ---------------------------------------------------------------------------

function ipv4IsPrivate(ip) {
  const [a, b] = ip.split('.').map(Number);
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 169 && b === 254) return true; // link-local + cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 192 && b === 0) return true; // IETF protocol assignments
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a === 198 && (b === 18 || b === 19)) return true; // benchmarking
  if (a >= 224) return true; // multicast + reserved
  return false;
}

function ipv6IsPrivate(ip) {
  const lower = ip.toLowerCase();
  if (lower === '::' || lower === '::1') return true;
  // IPv4-mapped (::ffff:1.2.3.4) — judge by the embedded v4 address.
  const mapped = lower.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return ipv4IsPrivate(mapped[1]);
  const head = parseInt(lower.split(':')[0] || '0', 16);
  if ((head & 0xfe00) === 0xfc00) return true; // fc00::/7 unique local
  if ((head & 0xffc0) === 0xfe80) return true; // fe80::/10 link local
  if ((head & 0xff00) === 0xff00) return true; // ff00::/8 multicast
  return false;
}

function isBlockedAddress(ip) {
  const version = net.isIP(ip);
  if (version === 4) return ipv4IsPrivate(ip);
  if (version === 6) return ipv6IsPrivate(ip);
  return true; // not an IP literal we understand — refuse
}

/**
 * Validates a proxy target. Rejects non-http(s) schemes, non-standard ports and
 * any hostname that resolves to a private / loopback / link-local address, which
 * is what stops the proxy being used to reach internal services or cloud
 * metadata endpoints.
 */
async function assertSafeTarget(rawUrl) {
  let target;
  try {
    target = new URL(rawUrl);
  } catch {
    throw new Error('Malformed target URL');
  }

  if (target.protocol !== 'http:' && target.protocol !== 'https:') {
    throw new Error(`Unsupported scheme: ${target.protocol}`);
  }

  const port = target.port === '' ? (target.protocol === 'https:' ? 443 : 80) : Number(target.port);
  if (port !== 80 && port !== 443) {
    throw new Error(`Blocked port: ${port}`);
  }

  const hostname = target.hostname.replace(/^\[|\]$/g, '');
  if (net.isIP(hostname)) {
    if (isBlockedAddress(hostname)) throw new Error(`Blocked address: ${hostname}`);
    return target;
  }

  let records;
  try {
    records = await dns.lookup(hostname, { all: true });
  } catch {
    throw new Error(`Cannot resolve host: ${hostname}`);
  }
  if (records.length === 0) throw new Error(`Cannot resolve host: ${hostname}`);
  for (const record of records) {
    if (isBlockedAddress(record.address)) {
      throw new Error(`Blocked address for ${hostname}: ${record.address}`);
    }
  }
  return target;
}

/**
 * fetch() with manual redirect handling so every hop is re-validated. A target
 * that passes the check and then 302s to http://169.254.169.254 must not slip
 * through.
 */
async function safeFetch(initialUrl, options) {
  let current = initialUrl;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertSafeTarget(current);
    const response = await fetch(current, { ...options, redirect: 'manual' });

    const isRedirect = response.status >= 300 && response.status < 400;
    const location = response.headers.get('location');
    if (!isRedirect || !location) return response;

    if (response.body) {
      try {
        await response.body.cancel();
      } catch {
        /* body already discarded */
      }
    }
    current = new URL(location, current).toString();
    // 303, and 301/302 on POST, degrade to GET per fetch semantics.
    if (response.status === 303 || (options.method === 'POST' && response.status !== 307 && response.status !== 308)) {
      options = { ...options, method: 'GET', body: undefined };
    }
  }
  throw new Error('Too many redirects');
}

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

const PASS_THROUGH_HEADERS = [
  'content-type',
  'content-length',
  'content-range',
  'accept-ranges',
  'last-modified',
  'etag',
];

async function readRequestBody(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > MAX_REQUEST_BODY_BYTES) {
      const error = new Error('Request body too large');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  return chunks.length > 0 ? Buffer.concat(chunks) : undefined;
}

function consumeProxyQuota(req) {
  const now = Date.now();
  const key = req.socket.remoteAddress || 'unknown';
  for (const [address, bucket] of rateBuckets) {
    if (now - bucket.startedAt >= RATE_LIMIT_WINDOW_MS) {
      rateBuckets.delete(address);
    }
  }
  const current = rateBuckets.get(key);
  if (!current || now - current.startedAt >= RATE_LIMIT_WINDOW_MS) {
    if (rateBuckets.size >= 1024) return false;
    rateBuckets.set(key, { startedAt: now, count: 1 });
    return true;
  }
  if (current.count >= RATE_LIMIT_MAX) return false;
  current.count += 1;
  return true;
}

function allowedMethods(pathname) {
  if (pathname === '/cors-proxy' || pathname === '/proxy') {
    return new Set(['GET', 'POST', 'HEAD', 'OPTIONS']);
  }
  if (pathname === '/resolve') return new Set(['GET', 'OPTIONS']);
  if (pathname === '/youtube-decipher') return new Set(['POST', 'OPTIONS']);
  return new Set(['GET', 'HEAD', 'OPTIONS']);
}

function balancedBlock(source, openingBrace) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  for (let index = openingBrace; index < source.length; index++) {
    const char = source[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'" || char === '`') {
      quote = char;
    } else if (char === '{') {
      depth += 1;
    } else if (char === '}' && --depth === 0) {
      return source.slice(openingBrace, index + 1);
    }
  }
  return null;
}

function classifyTransformMethod(body) {
  if (/\.reverse\(/.test(body)) return 'reverse';
  if (/\.splice\(0,/.test(body)) return 'splice';
  if (/\.slice\(/.test(body)) return 'slice';
  if (/\[0\].*%.*\.length/.test(body)) return 'swap';
  return null;
}

function parseHelperMethods(playerSource, helperName) {
  const escaped = helperName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`(?:var\\s+)?${escaped}=\\{`).exec(playerSource);
  if (!match) throw new Error(`YouTube helper ${helperName} was not found`);
  const opening = playerSource.indexOf('{', match.index);
  const objectBody = balancedBlock(playerSource, opening);
  if (!objectBody) throw new Error(`YouTube helper ${helperName} was truncated`);

  const methods = new Map();
  const pattern = /([\w$]+):function\([^)]*\)\{/g;
  let method;
  while ((method = pattern.exec(objectBody)) !== null) {
    const methodOpening = objectBody.indexOf('{', method.index);
    const body = balancedBlock(objectBody, methodOpening);
    const operation = body && classifyTransformMethod(body);
    if (operation) methods.set(method[1], operation);
  }
  return methods;
}

function compileTransform(playerSource, match, notFoundMessage) {
  if (!match) throw new Error(notFoundMessage);
  const argumentName = match[2];
  const brace = playerSource.indexOf('{', match.index);
  const body = balancedBlock(playerSource, brace);
  if (!body) throw new Error('YouTube transform function was truncated');

  const helperCache = new Map();
  const operations = [];
  for (const statement of body.slice(1, -1).split(';')) {
    const helperCall = /([\w$]+)\.([\w$]+)\([^,]+(?:,([^\)]+))?\)/.exec(statement);
    if (helperCall && helperCall[1] !== argumentName) {
      const helperName = helperCall[1];
      const methods = helperCache.get(helperName) ||
        parseHelperMethods(playerSource, helperName);
      helperCache.set(helperName, methods);
      const type = methods.get(helperCall[2]);
      if (!type) throw new Error(`Unsupported YouTube transform ${helperCall[2]}`);
      const value = helperCall[3] == null ? 0 : Number.parseInt(helperCall[3], 10);
      if (!Number.isFinite(value)) throw new Error('Invalid YouTube transform argument');
      operations.push({ type, value });
      continue;
    }
    if (new RegExp(`${argumentName}\\.reverse\\(\\)`).test(statement)) {
      operations.push({ type: 'reverse', value: 0 });
    }
  }
  if (operations.length === 0) throw new Error('YouTube transform has no supported operations');

  return (input) => {
    let value = [...String(input)];
    for (const operation of operations) {
      const index = value.length === 0 ? 0 : operation.value % value.length;
      switch (operation.type) {
        case 'reverse':
          value.reverse();
          break;
        case 'splice':
          value.splice(0, operation.value);
          break;
        case 'slice':
          value = value.slice(operation.value);
          break;
        case 'swap': {
          const first = value[0];
          value[0] = value[index];
          value[index] = first;
          break;
        }
      }
    }
    return value.join('');
  };
}

/** Converts YouTube's small permutation program into a fixed opcode list.
 * No player JavaScript is evaluated by the server.
 */
function createYouTubeSignatureDecipher(playerSource) {
  const patterns = [
    /([\w$]+)=function\((\w+)\)\{\2=\2\.split\(""\)/,
    /function\s+([\w$]+)\((\w+)\)\{\2=\2\.split\(""\)/,
  ];
  let transformMatch = null;
  for (const pattern of patterns) {
    transformMatch = pattern.exec(playerSource);
    if (transformMatch) break;
  }
  return compileTransform(
    playerSource,
    transformMatch,
    'YouTube signature function was not found',
  );
}

function createYouTubeNDecipher(playerSource) {
  const nameMatch = /\.get\("n"\)\)&&\([^=]+=([\w$]+)\([^\)]+\)/.exec(playerSource) ||
    /\bn&&\(n=([\w$]+)\(n\)\)/.exec(playerSource);
  if (!nameMatch) return null;
  const escaped = nameMatch[1].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const patterns = [
    new RegExp(`(${escaped})=function\\((\\w+)\\)\\{\\2=\\2\\.split\\(""\\)`),
    new RegExp(`function\\s+(${escaped})\\((\\w+)\\)\\{\\2=\\2\\.split\\(""\\)`),
  ];
  let transformMatch = null;
  for (const pattern of patterns) {
    transformMatch = pattern.exec(playerSource);
    if (transformMatch) break;
  }
  if (!transformMatch) return null;
  return compileTransform(playerSource, transformMatch, 'YouTube n function was not found');
}

async function handleYouTubeDecipher(req, res) {
  const rawBody = await readRequestBody(req);
  let payload;
  try {
    payload = JSON.parse(rawBody ? rawBody.toString('utf8') : '{}');
  } catch {
    res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Invalid JSON body' }));
    return;
  }
  const playerUrl = String(payload.playerUrl || '');
  const ciphers = Array.isArray(payload.ciphers) ? payload.ciphers : [];
  if (!/^https:\/\/([\w-]+\.)?(youtube\.com|youtube-nocookie\.com)\//i.test(playerUrl) ||
      ciphers.length === 0 || ciphers.length > 100) {
    res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Invalid YouTube decipher request' }));
    return;
  }

  const upstream = await safeFetch(playerUrl, {
    method: 'GET',
    headers: { 'User-Agent': DEFAULT_USER_AGENT, Accept: 'application/javascript' },
  });
  if (!upstream.ok) throw new Error(`YouTube player returned ${upstream.status}`);
  const playerSource = await upstream.text();
  const decipher = createYouTubeSignatureDecipher(playerSource);
  const decipherN = createYouTubeNDecipher(playerSource);
  const urls = ciphers.map((cipher) => {
    const fields = new URLSearchParams(String(cipher));
    const mediaUrl = new URL(fields.get('url'));
    const signature = fields.get('s');
    if (!signature) throw new Error('Cipher has no signature');
    mediaUrl.searchParams.set(fields.get('sp') || 'signature', decipher(signature));
    const throttling = mediaUrl.searchParams.get('n');
    if (throttling && decipherN) mediaUrl.searchParams.set('n', decipherN(throttling));
    return mediaUrl.toString();
  });
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({ urls }));
}

async function handleProxy(req, res, requestUrl) {
  const targetUrl = requestUrl.searchParams.get('url');
  if (!targetUrl) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Missing "url" parameter');
    return;
  }

  const outboundHeaders = {
    'User-Agent': req.headers['x-proxy-user-agent'] || DEFAULT_USER_AGENT,
    Accept: req.headers['accept'] || '*/*',
    'Accept-Language': req.headers['accept-language'] || 'en-US,en;q=0.9',
  };

  // Forwarded so HTML5 <video> seeking works through the proxy.
  if (req.headers['range']) outboundHeaders['Range'] = req.headers['range'];

  let body;
  if (req.method === 'POST' || req.method === 'PUT') {
    body = await readRequestBody(req);
    if (req.headers['content-type']) {
      outboundHeaders['Content-Type'] = req.headers['content-type'];
    }
  }

  const abort = new AbortController();
  let timer;
  const armIdleTimeout = () => {
    clearTimeout(timer);
    timer = setTimeout(() => abort.abort(), PROXY_IDLE_TIMEOUT_MS);
  };
  armIdleTimeout();

  try {
    const methods = allowedMethods(requestUrl.pathname);
    if (!methods.has(req.method)) {
      res.writeHead(405, {
        'Content-Type': 'text/plain; charset=utf-8',
        Allow: [...methods].join(', '),
      });
      res.end('405 Method Not Allowed');
      return;
    }

    const upstream = await safeFetch(targetUrl, {
      method: req.method,
      headers: outboundHeaders,
      body,
      signal: abort.signal,
    });

    const responseHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Expose-Headers':
        'Content-Range, Content-Length, Accept-Ranges, Content-Type, Content-Disposition',
    };

    upstream.headers.forEach((value, key) => {
      if (PASS_THROUGH_HEADERS.includes(key.toLowerCase())) responseHeaders[key] = value;
    });

    // `?filename=` turns the proxied response into a browser download. This is
    // what makes cross-origin video saveable from the web build: the anchor
    // `download` attribute is ignored cross-origin, so the file has to arrive
    // same-origin with an attachment disposition.
    const filename = requestUrl.searchParams.get('filename');
    if (filename) {
      const ascii = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
      responseHeaders['Content-Disposition'] =
        `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(filename)}`;
    }

    res.writeHead(upstream.status, responseHeaders);

    if (upstream.body && req.method !== 'HEAD') {
      // pipeline() honours backpressure, so a 2 GB video does not get buffered
      // into memory the way a manual read/write loop would. Refreshing the
      // timer on data makes it an inactivity timeout rather than a 30-second
      // cap on the entire download.
      const activityMonitor = new Transform({
        transform(chunk, encoding, callback) {
          armIdleTimeout();
          callback(null, chunk);
        },
      });
      armIdleTimeout();
      await pipeline(Readable.fromWeb(upstream.body), activityMonitor, res);
    } else {
      res.end();
    }
  } catch (err) {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: String(err && err.message ? err.message : err) }));
    } else {
      res.destroy();
    }
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Follows a short link server-side and reports where it lands. Browsers cannot
 * observe a redirect chain, so the web build asks the proxy to expand t.co /
 * vm.tiktok.com / fb.watch links on its behalf.
 */
async function handleResolve(req, res, requestUrl) {
  const targetUrl = requestUrl.searchParams.get('url');
  if (!targetUrl) {
    res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Missing "url" parameter' }));
    return;
  }

  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 15000);
  try {
    let current = targetUrl;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      await assertSafeTarget(current);
      const response = await fetch(current, {
        method: 'GET',
        headers: { 'User-Agent': DEFAULT_USER_AGENT, Accept: '*/*' },
        redirect: 'manual',
        signal: abort.signal,
      });
      const location = response.headers.get('location');
      if (response.body) {
        try {
          await response.body.cancel();
        } catch {
          /* already discarded */
        }
      }
      if (response.status < 300 || response.status >= 400 || !location) break;
      current = new URL(location, current).toString();
    }
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ url: current }));
  } catch (err) {
    res.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: String(err && err.message ? err.message : err) }));
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Resolves a request path inside WEB_DIR, or returns null when the path escapes
 * it. `path.join(WEB_DIR, '/../../server.js')` normalises to a file outside the
 * web root, so the containment check has to happen after resolution.
 */
function resolveStaticPath(pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (decoded.includes('\0')) return null;

  const resolved = path.resolve(WEB_DIR, '.' + path.posix.normalize(decoded));
  if (resolved !== WEB_DIR && !resolved.startsWith(WEB_DIR + path.sep)) return null;
  return resolved;
}

async function handleStatic(req, res, requestUrl) {
  let filePath = resolveStaticPath(requestUrl.pathname);
  if (filePath === null) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('403 Forbidden');
    return;
  }

  let stat = await fsp.stat(filePath).catch(() => null);
  if (stat && stat.isDirectory()) {
    filePath = path.join(filePath, 'index.html');
    stat = await fsp.stat(filePath).catch(() => null);
  }

  // SPA fallback: unknown routes without a file extension render index.html so
  // client-side routing works. Missing assets still 404 honestly.
  if (!stat) {
    if (path.extname(requestUrl.pathname) !== '') {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found');
      return;
    }
    filePath = path.join(WEB_DIR, 'index.html');
    stat = await fsp.stat(filePath).catch(() => null);
    if (!stat) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found — run `flutter build web` first');
      return;
    }
  }

  const contentType = MIME_TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
  res.writeHead(200, {
    'Content-Type': contentType,
    'Content-Length': stat.size,
    'Cache-Control': filePath.endsWith('index.html') ? 'no-cache' : 'public, max-age=3600',
  });

  if (req.method === 'HEAD') {
    res.end();
    return;
  }

  try {
    await pipeline(fs.createReadStream(filePath), res);
  } catch {
    res.destroy();
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Range, X-Proxy-User-Agent');
  res.setHeader('Access-Control-Expose-Headers',
    'Content-Range, Content-Length, Accept-Ranges, Content-Type, Content-Disposition');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  let requestUrl;
  try {
    requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('400 Bad Request');
    return;
  }

  try {
    const isProxy = requestUrl.pathname === '/cors-proxy' ||
      requestUrl.pathname === '/proxy' || requestUrl.pathname === '/resolve' ||
      requestUrl.pathname === '/youtube-decipher';
    if (isProxy && !consumeProxyQuota(req)) {
      res.writeHead(429, {
        'Content-Type': 'application/json; charset=utf-8',
        'Retry-After': '60',
      });
      res.end(JSON.stringify({ error: 'Too many proxy requests' }));
      return;
    }

    if (requestUrl.pathname === '/cors-proxy' || requestUrl.pathname === '/proxy') {
      await handleProxy(req, res, requestUrl);
    } else if (requestUrl.pathname === '/resolve') {
      await handleResolve(req, res, requestUrl);
    } else if (requestUrl.pathname === '/youtube-decipher') {
      await handleYouTubeDecipher(req, res);
    } else {
      await handleStatic(req, res, requestUrl);
    }
  } catch (err) {
    if (!res.headersSent) {
      const status = Number.isInteger(err && err.statusCode) ? err.statusCode : 500;
      res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(status === 413 ? '413 Payload Too Large' : '500 Internal Server Error');
    } else {
      res.destroy();
    }
  }
});

if (require.main === module) {
  server.listen(PORT, HOST, () => {
    console.log(`NimbleClip web server running at http://${HOST}:${PORT}`);
    if (!fs.existsSync(WEB_DIR)) {
      console.warn(`! ${WEB_DIR} does not exist — run \`flutter build web\` first.`);
    }
  });
}

module.exports = {
  server,
  assertSafeTarget,
  resolveStaticPath,
  isBlockedAddress,
  consumeProxyQuota,
  readRequestBody,
  allowedMethods,
  createYouTubeSignatureDecipher,
  createYouTubeNDecipher,
};
