'use strict';

const test = require('node:test');
const assert = require('node:assert');

const {
  summarize,
  formatMarkdown,
} = require('../tool/summarize_live_extractors.js');

// Shapes taken from a real `flutter test --file-reporter json:` run of
// test/live_extractor_smoke_test.dart, trimmed to the fields the summary uses.
function report(lines) {
  return lines.map((line) => JSON.stringify(line)).join('\n');
}

const loadingStart = {
  test: {id: 1, name: 'loading test/live_extractor_smoke_test.dart'},
  type: 'testStart',
};
const loadingDone = {
  testID: 1,
  result: 'success',
  skipped: false,
  hidden: true,
  type: 'testDone',
};

test('names each failed case with the error that failed it', () => {
  const summary = summarize(
    report([
      loadingStart,
      loadingDone,
      {test: {id: 3, name: 'TikTok video'}, type: 'testStart'},
      {
        testID: 3,
        error: 'ExtractionException(tiktokServiceStatus)',
        isFailure: true,
        type: 'error',
      },
      {
        testID: 3,
        result: 'failure',
        skipped: false,
        hidden: false,
        type: 'testDone',
      },
      {success: false, type: 'done'},
    ]),
  );

  assert.deepStrictEqual(summary.failed, [
    {name: 'TikTok video', error: 'ExtractionException(tiktokServiceStatus)'},
  ]);
});

test('lists the cases that passed and ignores the hidden loading entry', () => {
  const summary = summarize(
    report([
      loadingStart,
      loadingDone,
      {test: {id: 3, name: 'X video'}, type: 'testStart'},
      {
        testID: 3,
        result: 'success',
        skipped: false,
        hidden: false,
        type: 'testDone',
      },
      {success: true, type: 'done'},
    ]),
  );

  assert.deepStrictEqual(summary.passed, ['X video']);
  assert.deepStrictEqual(summary.failed, []);
});

test('keeps a multi-line matcher failure on one line', () => {
  const summary = summarize(
    report([
      {test: {id: 2, name: 'TikTok slideshow'}, type: 'testStart'},
      {
        testID: 2,
        error: 'Expected: true\n  Actual: <false>\n',
        isFailure: true,
        type: 'error',
      },
      {
        testID: 2,
        result: 'failure',
        skipped: false,
        hidden: false,
        type: 'testDone',
      },
      {success: false, type: 'done'},
    ]),
  );

  assert.deepStrictEqual(summary.failed, [
    {name: 'TikTok slideshow', error: 'Expected: true — Actual: <false>'},
  ]);
});

// Without --dart-define=RUN_LIVE_EXTRACTOR_TESTS the whole suite skips and the
// runner still reports success. A run that checked nothing must not be able to
// close the health issue.
test('a run where every case skipped is not a passing run', () => {
  const summary = summarize(
    report([
      {test: {id: 3, name: 'TikTok video'}, type: 'testStart'},
      {
        testID: 3,
        result: 'success',
        skipped: true,
        hidden: false,
        type: 'testDone',
      },
      {success: true, type: 'done'},
    ]),
  );

  assert.deepStrictEqual(summary.skipped, ['TikTok video']);
  assert.strictEqual(summary.checkedAnything, false);
});

test('the markdown carries every failed case, its error and the run link', () => {
  const markdown = formatMarkdown(
    {
      passed: ['X video'],
      failed: [
        {name: 'TikTok video', error: 'ExtractionException(tiktokServiceStatus)'},
      ],
      skipped: [],
      checkedAnything: true,
    },
    'https://github.com/o/r/actions/runs/1',
  );

  assert.match(markdown, /TikTok video/);
  assert.match(markdown, /tiktokServiceStatus/);
  assert.match(markdown, /X video/);
  assert.match(markdown, /actions\/runs\/1/);
});

test('the markdown keeps third-party failure text inside one inert cell', () => {
  const markdown = formatMarkdown(
    {
      passed: [],
      failed: [
        {
          name: 'TikTok | video',
          error: '<b>refused</b> | `details` & more',
        },
      ],
      skipped: [],
      checkedAnything: true,
    },
    '',
  );

  assert.match(markdown, /TikTok &#124; video/);
  assert.match(
    markdown,
    /<code>&lt;b&gt;refused&lt;\/b&gt; &#124; `details` &amp; more<\/code>/,
  );
  assert.doesNotMatch(markdown, /<b>/);
});

const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// The auto-close step needs a machine-readable answer as well as the comment
// body, and it must come from the same parse — a run that skipped every case
// reports success but must not be allowed to close the health issue.
test('--github-output writes both the comment body and the checked flag', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'live-summary-'));
  const reportPath = path.join(dir, 'report.json');
  const outputPath = path.join(dir, 'github-output');
  fs.writeFileSync(
    reportPath,
    report([
      {test: {id: 3, name: 'TikTok video'}, type: 'testStart'},
      {
        testID: 3,
        error: 'ExtractionException(tiktokServiceStatus)',
        isFailure: true,
        type: 'error',
      },
      {
        testID: 3,
        result: 'failure',
        skipped: false,
        hidden: false,
        type: 'testDone',
      },
      {success: false, type: 'done'},
    ]),
  );
  fs.writeFileSync(outputPath, '');

  execFileSync(
    process.execPath,
    [
      path.join(__dirname, '..', 'tool', 'summarize_live_extractors.js'),
      reportPath,
      'https://github.com/o/r/actions/runs/1',
      '--github-output',
    ],
    {env: {...process.env, GITHUB_OUTPUT: outputPath}},
  );

  const written = fs.readFileSync(outputPath, 'utf8');
  assert.match(written, /^markdown<</m);
  assert.match(written, /tiktokServiceStatus/);
  assert.match(written, /^checked=true$/m);
});

test('--github-output reports checked=false when every case skipped', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'live-summary-'));
  const reportPath = path.join(dir, 'report.json');
  const outputPath = path.join(dir, 'github-output');
  fs.writeFileSync(
    reportPath,
    report([
      {test: {id: 3, name: 'TikTok video'}, type: 'testStart'},
      {
        testID: 3,
        result: 'success',
        skipped: true,
        hidden: false,
        type: 'testDone',
      },
      {success: true, type: 'done'},
    ]),
  );
  fs.writeFileSync(outputPath, '');

  execFileSync(
    process.execPath,
    [
      path.join(__dirname, '..', 'tool', 'summarize_live_extractors.js'),
      reportPath,
      '',
      '--github-output',
    ],
    {env: {...process.env, GITHUB_OUTPUT: outputPath}},
  );

  assert.match(fs.readFileSync(outputPath, 'utf8'), /^checked=false$/m);
});
