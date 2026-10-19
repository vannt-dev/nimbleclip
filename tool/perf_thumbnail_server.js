// Thumbnails for the perf tests (integration_test/perf_*_test.dart): every path answers with
// the same picture, so each card gets its own URL (and its own decode) without the network.
// The emulator reaches this machine at 10.0.2.2.
//
//   node tool/perf_thumbnail_server.js [port] [picture]   (default 8765, the repository's screenshot.png)
//
// Use a picture the size of a real thumbnail (a 480x360 or 640x360 JPEG): the 1080x2400
// screenshot costs more to decode than anything a platform sends for a card.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const port = Number(process.argv[2] ?? 8765);
const file = process.argv[3] ?? path.join(__dirname, '..', 'screenshot.png');
const picture = fs.readFileSync(file);
const type = /\.jpe?g$/i.test(file) ? 'image/jpeg' : 'image/png';
let served = 0;

http
  .createServer((req, res) => {
    served += 1;
    res.writeHead(200, { 'content-type': type, 'content-length': picture.length });
    res.end(picture);
  })
  .listen(port, () => console.log(`thumbnails on http://0.0.0.0:${port}/ (${picture.length} bytes each)`));

process.on('SIGINT', () => {
  console.log(`served ${served} thumbnail(s)`);
  process.exit(0);
});
