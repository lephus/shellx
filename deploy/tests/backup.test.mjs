// Tests for deploy/backup/backup-once.sh with the local sqlite3 CLI (skipped without it):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'backup', 'backup-once.sh');
const hasSqlite = spawnSync('sqlite3', ['-version']).status === 0;

function world() {
  const root = mkdtempSync(join(tmpdir(), 'shellx-backup-'));
  const db = join(root, 'data', 'relay.db');
  const dir = join(root, 'backups');
  mkdirSync(dirname(db));
  mkdirSync(dir);
  const sql = (file, statement) => spawnSync('sqlite3', [file, statement], { encoding: 'utf8' }).stdout.trim();
  const backup = (day) =>
    spawnSync('sh', [script], { encoding: 'utf8', env: { ...process.env, DATA_DB: db, BACKUP_DIR: dir, BACKUP_DATE: day } });
  return { db, dir, sql, backup };
}

test('writes relay-<date>.db with the data, and keeps only the 14 newest', { skip: !hasSqlite }, () => {
  const w = world();
  w.sql(w.db, "PRAGMA journal_mode=WAL; CREATE TABLE users (id TEXT); INSERT INTO users VALUES ('u1');");
  for (let day = 1; day <= 16; day++) {
    const result = w.backup(`2026-01-${String(day).padStart(2, '0')}`);
    assert.equal(result.status, 0, result.stderr);
  }
  const files = readdirSync(w.dir).sort();
  assert.equal(files.length, 14);
  assert.equal(files[0], 'relay-2026-01-03.db');
  assert.equal(files.at(-1), 'relay-2026-01-16.db');
  assert.equal(w.sql(join(w.dir, 'relay-2026-01-16.db'), 'SELECT id FROM users;'), 'u1');
});

test('writes the backup file as mode 0600 (M9: umask 077, the database holds emails and password hashes)', { skip: !hasSqlite }, () => {
  const w = world();
  w.sql(w.db, "PRAGMA journal_mode=WAL; CREATE TABLE users (id TEXT); INSERT INTO users VALUES ('u1');");
  const result = w.backup('2026-03-01');
  assert.equal(result.status, 0, result.stderr);
  const mode = statSync(join(w.dir, 'relay-2026-03-01.db')).mode & 0o777;
  assert.equal(mode.toString(8), '600');
});

test('hands the backup file to the owner of the backups folder, so the deploy user can copy it (R5)', { skip: !hasSqlite }, () => {
  const w = world();
  w.sql(w.db, "PRAGMA journal_mode=WAL; CREATE TABLE users (id TEXT); INSERT INTO users VALUES ('u1');");
  // A fake chown on PATH records the call: the container runs as root, the test does not.
  const bin = join(dirname(w.dir), 'bin');
  const log = join(dirname(w.dir), 'chown.log');
  mkdirSync(bin);
  writeFileSync(join(bin, 'chown'), `#!/bin/sh\necho "$*" >> "${log}"\n`);
  chmodSync(join(bin, 'chown'), 0o755);
  const result = spawnSync('sh', [script], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, DATA_DB: w.db, BACKUP_DIR: w.dir, BACKUP_DATE: '2026-04-01' },
  });
  assert.equal(result.status, 0, result.stderr);
  const { uid, gid } = statSync(w.dir);
  assert.equal(readFileSync(log, 'utf8'), `${uid}:${gid} ${join(w.dir, 'relay-2026-04-01.db')}\n`);
  const mode = statSync(join(w.dir, 'relay-2026-04-01.db')).mode & 0o777;
  assert.equal(mode.toString(8), '600');
});

test('a missing database is skipped with one line: no empty database, no backup, nothing rotated', { skip: !hasSqlite }, () => {
  const w = world();
  const result = w.backup('2026-02-01');
  assert.equal(result.status, 1);
  assert.equal(result.stderr, `backup: skipped 2026-02-01: ${w.db} is missing or empty\n`);
  assert.equal(existsSync(w.db), false);
  assert.deepEqual(readdirSync(w.dir), []);
});

test('an unreadable database is skipped with one line and leaves no partial file', { skip: !hasSqlite }, () => {
  const w = world();
  writeFileSync(w.db, 'this is not a database '.repeat(100));
  const result = w.backup('2026-02-02');
  assert.equal(result.status, 1);
  assert.equal(result.stderr, `backup: skipped 2026-02-02: cannot read ${w.db} (is the relay running?)\n`);
  assert.deepEqual(readdirSync(w.dir), []);
});
