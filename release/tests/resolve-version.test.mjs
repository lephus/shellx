import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../scripts/resolve-version.mjs', import.meta.url));

// A stand-in for download.shellx.pro that serves exactly the listed paths.
async function downloads(published) {
  const server = createServer((req, res) => {
    const path = new URL(req.url, 'http://x').pathname;
    res.statusCode = published.includes(path) ? 200 : 404;
    res.end();
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, url: `http://127.0.0.1:${server.address().port}` };
}

function run(env) {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-resolve-'));
  const pubspec = join(dir, 'pubspec.yaml');
  const relay = join(dir, 'relay.env');
  const site = join(dir, 'site.config.json');
  const output = join(dir, 'github_output');
  writeFileSync(pubspec, `name: shellx_desktop\nversion: ${env.pubspecVersion}\n`);
  writeFileSync(relay, `LATEST_AGENT_VERSION=${env.released}\n`);
  writeFileSync(site, JSON.stringify({ desktopVersion: env.site ?? env.released }));
  writeFileSync(output, '');
  const child = spawn(process.execPath, [script], {
    env: {
      PATH: process.env.PATH,
      GITHUB_EVENT_NAME: env.event,
      GITHUB_REF_TYPE: 'branch',
      GITHUB_REF_NAME: env.branch ?? 'main',
      INPUT_DRY_RUN: env.dryRun ?? '',
      PUBSPEC_PATH: pubspec,
      RELAY_ENV_PATH: relay,
      SITE_CONFIG_PATH: site,
      DOWNLOAD_BASE_URL: env.baseUrl ?? 'http://127.0.0.1:1',
      GITHUB_OUTPUT: output,
      RETRY_DELAY_MS: env.retryDelayMs ?? '1',
    },
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  return new Promise((resolve) => child.on('close', (status) => resolve({ status, stdout, stderr, output: readFileSync(output, 'utf8') })));
}

test('a push builds a version download.shellx.pro does not serve yet', async () => {
  const { server, url } = await downloads([]);
  try {
    const result = await run({ event: 'push', pubspecVersion: '1.0.1+2', released: '1.0.0', baseUrl: url });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, 'version=1.0.1\ndry_run=false\nbuild=true\nannounce=false\n');
  } finally {
    server.close();
  }
});

test('a push skips a version that is already published', async () => {
  const { server, url } = await downloads(['/desktop/1.0.0/ShellX-1.0.0.dmg', '/desktop/1.0.0/ShellX-Setup-1.0.0.exe']);
  try {
    const result = await run({ event: 'push', pubspecVersion: '1.0.0+1', released: '1.0.0', baseUrl: url });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, 'version=1.0.0\ndry_run=false\nbuild=false\nannounce=false\n');
    assert.match(result.stdout, /already published/);
  } finally {
    server.close();
  }
});

test('a push stops on a half-published version', async () => {
  const { server, url } = await downloads(['/desktop/1.0.1/ShellX-1.0.1.dmg']);
  try {
    const result = await run({ event: 'push', pubspecVersion: '1.0.1+2', released: '1.0.0', baseUrl: url });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /::error::only the dmg is published/);
  } finally {
    server.close();
  }
});

test('a push stops when download.shellx.pro cannot be reached', async () => {
  const result = await run({ event: 'push', pubspecVersion: '1.0.1+2', released: '1.0.0' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /::error::cannot check whether the dmg is published/);
});

test('a dry run always builds and never asks download.shellx.pro', async () => {
  const result = await run({ event: 'workflow_dispatch', branch: 'feat/x', dryRun: 'true', pubspecVersion: '1.0.1+2', released: '1.0.0' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, 'version=1.0.1\ndry_run=true\nbuild=true\nannounce=false\n');
});

test('a push re-announces a published version the relay or the website does not name yet', async () => {
  const { server, url } = await downloads(['/desktop/1.0.1/ShellX-1.0.1.dmg', '/desktop/1.0.1/ShellX-Setup-1.0.1.exe']);
  try {
    const result = await run({ event: 'push', pubspecVersion: '1.0.1+2', released: '1.0.0', site: '1.0.1', baseUrl: url });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, 'version=1.0.1\ndry_run=false\nbuild=false\nannounce=true\n');
  } finally {
    server.close();
  }
});

test('a push retries download.shellx.pro after a 5xx answer', async () => {
  let calls = 0;
  const server = createServer((req, res) => {
    calls += 1;
    res.statusCode = calls <= 2 ? 502 : 404;
    res.end();
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const result = await run({ event: 'push', pubspecVersion: '1.0.1+2', released: '1.0.0', baseUrl: `http://127.0.0.1:${server.address().port}`, retryDelayMs: '1' });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.output, /build=true/);
  } finally {
    server.close();
  }
});
