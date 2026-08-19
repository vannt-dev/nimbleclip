'use strict';

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const dns = require('dns/promises');
const net = require('net');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const PORT = Number(process.env.PORT || 8080);
// Bind to loopback by default: the CORS proxy is a dev convenience, not a
// service that should be reachable from the rest of the network.
const HOST = process.env.HOST || '127.0.0.1';
const WEB_DIR = path.resolve(__dirname, 'build', 'web');

const MAX_REDIRECTS = 5;
const PROXY_TIMEOUT_MS = 30000;
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
  'last-modified',
  'etag',
];

async function readRequestBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length > 0 ? Buffer.concat(chunks) : undefined;
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
  const timer = setTimeout(() => abort.abort(), PROXY_TIMEOUT_MS);

  try {
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
      'Accept-Ranges': 'bytes',
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
      // into memory the way a manual read/write loop would.
      await pipeline(Readable.fromWeb(upstream.body), res);
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
    if (requestUrl.pathname === '/cors-proxy' || requestUrl.pathname === '/proxy') {
      await handleProxy(req, res, requestUrl);
    } else if (requestUrl.pathname === '/resolve') {
      await handleResolve(req, res, requestUrl);
    } else {
      await handleStatic(req, res, requestUrl);
    }
  } catch (err) {
    if (!res.headersSent) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('500 Internal Server Error');
    } else {
      res.destroy();
    }
  }
});

if (require.main === module) {
  server.listen(PORT, HOST, () => {
    console.log(`SnapVideo web server running at http://${HOST}:${PORT}`);
    if (!fs.existsSync(WEB_DIR)) {
      console.warn(`! ${WEB_DIR} does not exist — run \`flutter build web\` first.`);
    }
  });
}

module.exports = { server, assertSafeTarget, resolveStaticPath, isBlockedAddress };
