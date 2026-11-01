#!/usr/bin/env node
// merge-settings.mjs: combina las capas de settings.json (base, sistema, maquina)
// y resuelve {{HOME}}. Sin dependencias externas; requiere Node >= 18.
//
// Uso: node merge-settings.mjs --dir <claude-code> --os <macos|linux|windows>
//        --machine <ruta> --home <ruta> --out <ruta>

import { readFileSync, writeFileSync, renameSync, lstatSync, unlinkSync, mkdirSync } from 'node:fs';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SISTEMAS = ['macos', 'linux', 'windows'];
const CLAVES_MAQUINA = { IDE_MCP: ['yes', 'no'] };

function esObjeto(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function fusionar(a, b) {
  if (!esObjeto(a) || !esObjeto(b)) return structuredClone(b);
  const out = structuredClone(a);
  for (const [k, v] of Object.entries(b)) {
    out[k] = k in out ? fusionar(out[k], v) : structuredClone(v);
  }
  return out;
}

// Objetos clave a clave; listas y escalares de la capa superior reemplazan.
// Orden: base, luego sistema, luego maquina. No muta las entradas.
// Nota sobre `machine`: parseMachineEnv devuelve {IDE_MCP}, pero esa clave no
// pertenece a settings.json (los MCP viven en ~/.claude.json y los registra el
// instalador). Por eso la CLI pasa {} aqui; el tercer argumento queda para
// sobrescrituras por equipo que sean fragmentos validos de settings.
export function mergeSettings(base, osLayer, machine) {
  return fusionar(fusionar(base ?? {}, osLayer ?? {}), machine ?? {});
}

// Sustituye {{HOME}} en todas las cadenas (valores y claves de objetos). Opera
// sobre el objeto, no sobre el texto JSON, asi JSON.stringify escapa despues
// barras invertidas y comillas del valor.
export function render(value, vars) {
  const sub = (s) => s.replaceAll('{{HOME}}', () => vars.HOME);
  if (typeof value === 'string') return sub(value);
  if (Array.isArray(value)) return value.map((x) => render(x, vars));
  if (esObjeto(value)) {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [sub(k), render(v, vars)]));
  }
  return value;
}

// Lee texto tipo CLAVE=valor (admite comentarios # y lineas vacias).
export function parseMachineEnv(text) {
  const out = {};
  for (const [i, cruda] of text.split(/\r?\n/).entries()) {
    const linea = cruda.trim();
    if (!linea || linea.startsWith('#')) continue;
    const eq = linea.indexOf('=');
    if (eq < 1) throw new Error(`machine.env linea ${i + 1}: formato invalido`);
    const clave = linea.slice(0, eq).trim();
    const valor = linea.slice(eq + 1).trim();
    if (!(clave in CLAVES_MAQUINA)) throw new Error(`machine.env: clave desconocida ${clave}`);
    if (!CLAVES_MAQUINA[clave].includes(valor)) {
      throw new Error(`machine.env: ${clave} debe ser ${CLAVES_MAQUINA[clave].join('|')} (recibido "${valor}")`);
    }
    out[clave] = valor;
  }
  for (const clave of Object.keys(CLAVES_MAQUINA)) {
    if (!(clave in out)) throw new Error(`machine.env: falta la clave ${clave}`);
  }
  return out;
}

function escribirAtomico(ruta, texto) {
  mkdirSync(dirname(ruta), { recursive: true });
  try {
    // Si existe un enlace simbolico, se quita: el resultado es siempre archivo regular.
    if (lstatSync(ruta).isSymbolicLink()) unlinkSync(ruta);
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  const tmp = join(dirname(ruta), `.${basename(ruta)}.${process.pid}.tmp`);
  writeFileSync(tmp, texto);
  renameSync(tmp, ruta); // rename reemplaza el destino, no sigue enlaces
}

function leerJson(ruta) {
  try {
    return JSON.parse(readFileSync(ruta, 'utf8'));
  } catch (e) {
    throw new Error(`no se pudo leer JSON ${ruta}: ${e.message}`);
  }
}

function args(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i];
    if (!k.startsWith('--') || argv[i + 1] === undefined) throw new Error(`argumento invalido: ${k}`);
    out[k.slice(2)] = argv[i + 1];
  }
  for (const k of ['dir', 'os', 'machine', 'home', 'out']) {
    if (!out[k]) throw new Error(`falta --${k}`);
  }
  if (!SISTEMAS.includes(out.os)) throw new Error(`--os debe ser ${SISTEMAS.join('|')}`);
  return out;
}

function main() {
  const a = args(process.argv.slice(2));
  let texto;
  try {
    texto = readFileSync(a.machine, 'utf8');
  } catch {
    throw new Error(`no existe el archivo machine: ${a.machine}`);
  }
  parseMachineEnv(texto); // valida; IDE_MCP no entra en settings.json
  const base = leerJson(join(a.dir, 'settings.base.json'));
  const capaOs = leerJson(join(a.dir, `settings.${a.os}.json`));
  const final = render(mergeSettings(base, capaOs, {}), { HOME: a.home });
  escribirAtomico(a.out, JSON.stringify(final, null, 2) + '\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (e) {
    console.error(`merge-settings: ${e.message}`);
    process.exit(1);
  }
}
