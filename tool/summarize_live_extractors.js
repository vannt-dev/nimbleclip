'use strict';

// Turns a `flutter test --file-reporter json:` report of the live extractor
// smoke checks into something a person can act on without opening the run log.
//
// The health workflow used to comment only "Scheduled public extractor checks
// failed" plus a link, so six consecutive failures were indistinguishable from
// each other and every one of them cost a trip into the logs. The failure kind
// is what says who is at fault: `tiktokServiceStatus` means the upstream
// service answered non-200, while `tiktokInvalidData` carries that service's
// own message, which means it answered and refused.

const fs = require('node:fs');

function parseEvents(reportText) {
  const events = [];
  for (const line of reportText.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      events.push(JSON.parse(trimmed));
    } catch {
      // The reporter writes one JSON object per line; anything else is noise
      // from a crashing run and must not take the summary down with it.
    }
  }
  return events;
}

function tidyError(error) {
  return String(error)
    .split('\n')
    .map((part) => part.trim())
    .filter(Boolean)
    .join(' — ');
}

function escapeTableCell(value) {
  // The error can contain wording returned by a third-party extractor. Keep it
  // inert in the issue comment and prevent pipes from adding table columns.
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\|/g, '&#124;');
}

function summarize(reportText) {
  const events = parseEvents(reportText);
  const names = new Map();
  const errors = new Map();
  const passed = [];
  const failed = [];
  const skipped = [];

  for (const event of events) {
    if (event.type === 'testStart' && event.test) {
      names.set(event.test.id, event.test.name);
    } else if (event.type === 'error' && !errors.has(event.testID)) {
      // Only the first error names the reason; later ones are usually the
      // teardown noise that follows it.
      errors.set(event.testID, tidyError(event.error));
    } else if (event.type === 'testDone') {
      if (event.hidden) continue;
      const name = names.get(event.testID) ?? `test ${event.testID}`;
      if (event.skipped) {
        skipped.push(name);
      } else if (event.result === 'success') {
        passed.push(name);
      } else {
        failed.push({name, error: errors.get(event.testID) ?? event.result});
      }
    }
  }

  return {
    passed,
    failed,
    skipped,
    // A suite run without --dart-define=RUN_LIVE_EXTRACTOR_TESTS skips every
    // case and still reports success. That run checked nothing, so it must not
    // be allowed to stand in for a healthy one.
    checkedAnything: passed.length > 0 || failed.length > 0,
  };
}

function formatMarkdown(summary, runUrl) {
  const lines = [];

  if (summary.failed.length) {
    lines.push('Scheduled public extractor checks failed.', '');
    lines.push('| Check | Failure |', '| --- | --- |');
    for (const {name, error} of summary.failed) {
      lines.push(
        `| ${escapeTableCell(name)} | ` +
          `<code>${escapeTableCell(error)}</code> |`,
      );
    }
  } else if (!summary.checkedAnything) {
    lines.push(
      'Scheduled public extractor checks ran without checking anything —',
      'every case skipped, so `RUN_LIVE_EXTRACTOR_TESTS` was probably unset.',
    );
  } else {
    lines.push('Public extractor checks are passing again.');
  }

  if (summary.passed.length) {
    lines.push('', `Passing: ${summary.passed.join(', ')}.`);
  }
  if (summary.skipped.length) {
    lines.push('', `Skipped: ${summary.skipped.join(', ')}.`);
  }
  if (runUrl) {
    lines.push('', `Run: ${runUrl}`);
  }

  return lines.join('\n');
}

module.exports = {summarize, formatMarkdown};

if (require.main === module) {
  const args = process.argv.slice(2);
  const toGithubOutput = args.includes('--github-output');
  const [reportPath, runUrl] = args.filter((arg) => !arg.startsWith('--'));
  if (!reportPath) {
    console.error(
      'usage: node tool/summarize_live_extractors.js <report.json> [runUrl]' +
        ' [--github-output]',
    );
    process.exit(2);
  }

  const summary = summarize(fs.readFileSync(reportPath, 'utf8'));
  const markdown = formatMarkdown(summary, runUrl);

  if (!toGithubOutput) {
    process.stdout.write(markdown);
  } else {
    // A delimiter the body cannot contain, so a failure message carrying
    // newlines cannot break out of the heredoc and forge further outputs.
    const delimiter = `SUMMARY_${Date.now()}_${process.pid}`;
    fs.appendFileSync(
      process.env.GITHUB_OUTPUT,
      `markdown<<${delimiter}\n${markdown}\n${delimiter}\n` +
        `checked=${summary.checkedAnything}\n`,
    );
  }
}
