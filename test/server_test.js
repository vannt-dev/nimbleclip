'use strict';

const assert = require('node:assert/strict');
const { Readable } = require('node:stream');
const test = require('node:test');

const {
  consumeProxyQuota,
  allowedMethods,
  isBlockedAddress,
  readRequestBody,
  resolveStaticPath,
} = require('../server');

test('routes expose only the methods they implement', () => {
  assert.equal(allowedMethods('/proxy').has('POST'), true);
  assert.equal(allowedMethods('/proxy').has('DELETE'), false);
  assert.equal(allowedMethods('/resolve').has('POST'), false);
  assert.equal(allowedMethods('/assets/app.js').has('POST'), false);
});

test('SSRF guard blocks private and link-local addresses', () => {
  assert.equal(isBlockedAddress('127.0.0.1'), true);
  assert.equal(isBlockedAddress('10.0.0.1'), true);
  assert.equal(isBlockedAddress('169.254.169.254'), true);
  assert.equal(isBlockedAddress('8.8.8.8'), false);
});

test('static resolver cannot escape build/web', () => {
  const traversal = resolveStaticPath('/../../server.js');
  assert.ok(traversal.includes(`build${require('node:path').sep}web`));
  assert.notEqual(traversal, require('node:path').resolve(__dirname, '..', 'server.js'));
  assert.ok(resolveStaticPath('/assets/app.js').endsWith('assets\\app.js') ||
      resolveStaticPath('/assets/app.js').endsWith('assets/app.js'));
});

test('proxy quota rejects requests after the per-minute allowance', () => {
  const request = { socket: { remoteAddress: 'test-client-rate-limit' } };
  for (let i = 0; i < 120; i++) assert.equal(consumeProxyQuota(request), true);
  assert.equal(consumeProxyQuota(request), false);
});

test('request body reader rejects payloads larger than one MiB', async () => {
  const request = Readable.from([Buffer.alloc(1024 * 1024 + 1)]);
  await assert.rejects(readRequestBody(request), (error) => {
    assert.equal(error.statusCode, 413);
    return true;
  });
});
