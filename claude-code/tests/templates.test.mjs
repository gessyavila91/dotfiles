// Pruebas de las plantillas de settings. Todo en directorios temporales.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, copyFileSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { filtrarOs, render, VARS_SISTEMA } from '../lib/merge-settings.mjs';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = join(DIR, 'lib', 'merge-settings.mjs');

test('rendered_macos_equals_current_settings', (t) => {
  const real = process.env.CLAUDE_REAL_SETTINGS || join(homedir(), '.claude', 'settings.json');
  if (!existsSync(real)) {
    console.warn(`AVISO: no existe ${real}; se salta la comparacion`);
    return t.skip('settings.json real ausente');
  }
  const tmp = mkdtempSync(join(tmpdir(), 'tpl-'));
  const machine = join(tmp, 'machine.env');
  copyFileSync(join(DIR, 'machine.env.example'), machine);
  const out = join(tmp, 'settings.json');
  const r = spawnSync('node', [SCRIPT, '--dir', DIR, '--os', 'macos', '--machine', machine, '--home', homedir(), '--out', out], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(readFileSync(out, 'utf8')), JSON.parse(readFileSync(real, 'utf8')));
});

test('no_literal_home_paths_in_templates', () => {
  const archivos = readdirSync(DIR).filter((f) => /^settings\..*\.json$|^machine\.env\.example$/.test(f));
  assert.ok(archivos.length >= 5);
  for (const f of archivos) {
    const txt = readFileSync(join(DIR, f), 'utf8');
    assert.ok(!/\/[U]sers\//.test(txt) && !/\/[h]ome\/[a-z]/i.test(txt) && !txt.includes(homedir()), `ruta literal en ${f}`);
  }
});

test('windows_layer_is_small', () => {
  const lineas = readFileSync(join(DIR, 'settings.windows.json'), 'utf8').split('\n').length;
  assert.ok(lineas < 20, `settings.windows.json tiene ${lineas} lineas`);
});

function generar(os) {
  const tmp = mkdtempSync(join(tmpdir(), 'tpl-'));
  const machine = join(tmp, 'machine.env');
  copyFileSync(join(DIR, 'machine.env.example'), machine);
  const out = join(tmp, 'settings.json');
  const r = spawnSync('node', [SCRIPT, '--dir', DIR, '--os', os, '--machine', machine, '--home', tmp, '--out', out], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return readFileSync(out, 'utf8');
}

test('os_filter_keeps_matching_discards_others_and_strips_mark', () => {
  const v = { l: [{ __os: ['macos'], a: 1 }, { b: 2 }, { __os: ['linux', 'windows'], c: 3 }], __agent: true, k: [{ '__agent-dag': true }] };
  assert.deepEqual(filtrarOs(v, 'macos'), { l: [{ a: 1 }, { b: 2 }], __agent: true, k: [{ '__agent-dag': true }] });
  assert.deepEqual(filtrarOs(v, 'linux').l, [{ b: 2 }, { c: 3 }]);
  assert.ok(!JSON.stringify(filtrarOs(v, 'windows')).includes('__os'));
});

test('node_variable_per_system', () => {
  assert.equal(render('{{NODE}} x', { HOME: 'h', ...VARS_SISTEMA.macos }), '/usr/local/bin/node x');
  assert.equal(render('{{NODE}} x', { HOME: 'h', ...VARS_SISTEMA.linux }), 'node x');
  assert.equal(render('{{NODE}}', { HOME: 'h', ...VARS_SISTEMA.windows }), 'node');
});

test('linux_and_windows_have_no_macos_only_commands', () => {
  for (const os of ['linux', 'windows']) {
    const txt = generar(os);
    assert.ok(!txt.includes('notifyutil'), `${os}: notifyutil`);
    assert.ok(!txt.includes('/usr/local/bin/node'), `${os}: ruta de node`);
    assert.ok(!txt.includes('__os'), `${os}: marca __os`);
  }
});
