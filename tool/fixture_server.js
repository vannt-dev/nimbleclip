#!/usr/bin/env node
'use strict';

/**
 * Fixture server for `integration_test/android_storage_test.dart`.
 *
 * Serves a real MP4 over plain HTTP with byte-range support so the on-device
 * tests can exercise the full download path, including resume. An Android
 * emulator reaches the host machine at 10.0.2.2.
 *
 *   node tool/fixture_server.js
 *   flutter test integration_test/android_storage_test.dart -d emulator-5554
 *
 * The sample is downloaded once into tool/.fixtures/ (git-ignored).
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const PORT = Number(process.env.FIXTURE_PORT || 8097);
const FIXTURE_DIR = path.join(__dirname, '.fixtures');
const FIXTURE_FILE = path.join(FIXTURE_DIR, 'sample.mp4');
const SAMPLE_URL = 'https://download.samplelib.com/mp4/sample-5s.mp4';

async function ensureFixture() {
  if (fs.existsSync(FIXTURE_FILE) && fs.statSync(FIXTURE_FILE).size > 0) return;

  fs.mkdirSync(FIXTURE_DIR, { recursive: true });
  process.stdout.write(`Downloading sample video from ${SAMPLE_URL} ... `);
  const response = await fetch(SAMPLE_URL);
  if (!response.ok) throw new Error(`sample download failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());

  // Reject anything that is not actually an MP4; an error page saved as .mp4
  // would make the gallery test fail for the wrong reason.
  if (bytes.subarray(4, 8).toString('ascii') !== 'ftyp') {
    throw new Error('downloaded sample is not an MP4 (no ftyp box)');
  }
  fs.writeFileSync(FIXTURE_FILE, bytes);
  console.log(`${bytes.length} bytes`);
}

/** One PNG chunk: length, type, payload, CRC32 over type+payload. */
function pngChunk(type, payload) {
  const header = Buffer.alloc(8);
  header.writeUInt32BE(payload.length, 0);
  header.write(type, 4, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([header.subarray(4), payload])), 0);
  return Buffer.concat([header, payload, crc]);
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// A deterministic opaque RGB PNG. The gradient keeps it from compressing down
// to nothing, so the transfer stays representative of a real photo.
function buildPng(width, height) {
  const raw = Buffer.alloc(height * (1 + width * 3));
  let offset = 0;
  for (let y = 0; y < height; y++) {
    raw[offset++] = 0; // filter: none
    for (let x = 0; x < width; x++) {
      raw[offset++] = (x * 7 + y * 3) & 0xff;
      raw[offset++] = (x * 3 + y * 11) & 0xff;
      raw[offset++] = (x ^ y) & 0xff;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

const pngCache = new Map();

function serve() {
  const size = fs.statSync(FIXTURE_FILE).size;
  const rangeRequestCounts = new Map();

  http
    .createServer((req, res) => {
      if (req.url === '/health') {
        const body = JSON.stringify({
          service: 'nimbleclip-fixture',
          status: 'ok',
        });
        res.writeHead(200, {
          'Content-Type': 'application/json; charset=utf-8',
          'Content-Length': Buffer.byteLength(body),
        });
        return res.end(body);
      }

      if (req.url.startsWith('/invalid.mp4')) {
        const body = Buffer.from('<html><body>expired media link</body></html>');
        res.writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Content-Length': body.length,
        });
        return res.end(body);
      }

      if (req.url.startsWith('/large.png')) {
        const cacheKey = '1080x1350';
        let png = pngCache.get(cacheKey);
        if (!png) {
          png = buildPng(1080, 1350);
          pngCache.set(cacheKey, png);
        }
        res.writeHead(200, {
          'Content-Type': 'image/png',
          'Content-Length': png.length,
          'Cache-Control': 'no-store',
        });
        return res.end(png);
      }

      // `?norange` simulates a server that ignores Range, so the test can check
      // the client restarts cleanly instead of appending onto a partial file.
      const ignoreRange = req.url.includes('norange');
      const flakyRange = req.url.includes('flakyrange');
      const acceptRanges = ignoreRange ? 'none' : 'bytes';
      let range = ignoreRange ? null : req.headers.range;

      if (flakyRange && range) {
        const count = (rangeRequestCounts.get(req.url) || 0) + 1;
        rangeRequestCounts.set(req.url, count);
        // Let the one-byte capability probe succeed, then deliberately ignore
        // Range on the actual download. The client must discard its partial
        // file and restart rather than append this 200 response.
        if (count > 1) range = null;
      }

      if (req.method === 'HEAD') {
        res.writeHead(200, {
          'Content-Type': 'video/mp4',
          'Content-Length': size,
          'Accept-Ranges': acceptRanges,
        });
        return res.end();
      }

      const match = range && /bytes=(\d+)-(\d*)/.exec(range);
      if (match) {
        const start = Number(match[1]);
        const end = match[2] ? Number(match[2]) : size - 1;
        res.writeHead(206, {
          'Content-Type': 'video/mp4',
          'Content-Range': `bytes ${start}-${end}/${size}`,
          'Content-Length': end - start + 1,
          'Accept-Ranges': 'bytes',
        });
        return fs.createReadStream(FIXTURE_FILE, { start, end }).pipe(res);
      }

      res.writeHead(200, {
        'Content-Type': 'video/mp4',
        'Content-Length': size,
        'Accept-Ranges': acceptRanges,
      });
      fs.createReadStream(FIXTURE_FILE).pipe(res);
    })
    .listen(PORT, '0.0.0.0', () => {
      console.log(`Fixture server on http://0.0.0.0:${PORT} (${size} bytes)`);
      console.log('Android emulator reaches it at http://10.0.2.2:' + PORT);
    });
}

ensureFixture().then(serve).catch((err) => {
  console.error(err.message);
  process.exit(1);
});
