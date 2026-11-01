// Pruebas de merge-settings.mjs. Todo en directorios temporales; HOME nunca es el real.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, symlinkSync, lstatSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { mergeSettings, render, parseMachineEnv } from '../lib/merge-settings.mjs';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), '..', 'lib', 'merge-settings.mjs');

test('objects_merge_key_by_key', () => {
  const base = { permissions: { defaultMode: 'auto', x: 1 }, theme: 'dark' };
  const os = { permissions: { x: 2 }, tui: 'a' };
  const out = mergeSettings(base, os, {});
  assert.deepEqual(out, { permissions: { defaultMode: 'auto', x: 2 }, theme: 'dark', tui: 'a' });
  assert.deepEqual(base.permissions, { defaultMode: 'auto', x: 1 }, 'no muta la entrada');
});

test('lists_are_replaced_not_concatenated', () => {
  const out = mergeSettings({ l: [1, 2], o: { l: ['a'] } }, { l: [3] }, { o: { l: ['b', 'c'] } });
  assert.deepEqual(out, { l: [3], o: { l: ['b', 'c'] } });
});

test('render_replaces_home_everywhere', () => {
  const v = { a: '{{HOME}}/x', n: [{ c: 'cd {{HOME}} && {{HOME}}' }], k: 3, b: true, z: null };
  const out = render(v, { HOME: '/tmp/casa-falsa' });
  assert.deepEqual(out, { a: '/tmp/casa-falsa/x', n: [{ c: 'cd /tmp/casa-falsa && /tmp/casa-falsa' }], k: 3, b: true, z: null });
});

test('home_with_spaces_and_backslashes', () => {
  const home = 'C:\\Users\\Nombre Apellido';
  const out = render({ cmd: '{{HOME}}\\.claude\\hook.mjs' }, { HOME: home });
  const parsed = JSON.parse(JSON.stringify(out));
  assert.equal(parsed.cmd, home + '\\.claude\\hook.mjs');
});

test('machine_env_invalid_fails', () => {
  assert.deepEqual(parseMachineEnv('# c\n\nIDE_MCP=yes\n'), { IDE_MCP: 'yes' });
  assert.deepEqual(parseMachineEnv('IDE_MCP=no'), { IDE_MCP: 'no' });
  assert.throws(() => parseMachineEnv('FOO=1\nIDE_MCP=yes'), /FOO/);
  assert.throws(() => parseMachineEnv('IDE_MCP=maybe'), /IDE_MCP/);
  assert.throws(() => parseMachineEnv(''), /IDE_MCP/);
  // archivo ausente: lo detecta la CLI
  const d = mkdtempSync(join(tmpdir(), 'ms-'));
  const r = spawnSync('node', [SCRIPT, '--dir', d, '--os', 'linux', '--machine', join(d, 'no-existe.env'),
    '--home', '/tmp/casa-falsa', '--out', join(d, 'o.json')], { encoding: 'utf8' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /machine/);
});

test('cli_writes_valid_json_and_never_a_symlink', () => {
  const d = mkdtempSync(join(tmpdir(), 'ms-'));
  const cfg = join(d, 'cfg');
  mkdirSync(cfg);
  writeFileSync(join(cfg, 'settings.base.json'), JSON.stringify({ theme: 'dark', hooks: { c: '{{HOME}}/b' } }));
  writeFileSync(join(cfg, 'settings.windows.json'), JSON.stringify({ hooks: { c: '{{HOME}}\\b.mjs' } }));
  const machine = join(d, 'machine.env');
  writeFileSync(machine, 'IDE_MCP=no\n');
  const home = 'C:\\Users\\Nombre Apellido';
  const out = join(d, 'settings.json');
  const target = join(d, 'otro.json');
  writeFileSync(target, 'ORIGINAL');
  symlinkSync(target, out);
  const r = spawnSync('node', [SCRIPT, '--dir', cfg, '--os', 'windows', '--machine', machine, '--home', home, '--out', out], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(!lstatSync(out).isSymbolicLink());
  assert.equal(readFileSync(target, 'utf8'), 'ORIGINAL', 'no escribe a traves del enlace');
  assert.deepEqual(JSON.parse(readFileSync(out, 'utf8')), { theme: 'dark', hooks: { c: home + '\\b.mjs' } });
  // os desconocido
  const bad = spawnSync('node', [SCRIPT, '--dir', cfg, '--os', 'amiga', '--machine', machine, '--home', home, '--out', out], { encoding: 'utf8' });
  assert.notEqual(bad.status, 0);
});
