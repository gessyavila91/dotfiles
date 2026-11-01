#!/usr/bin/env node
// mcp-helper.mjs: apoyo JSON de mcp-register.sh (sin jq). Node >= 18.
//
//   plan <mcp.json> <machine.env> <home>
//       Imprime una linea "nombre<TAB>json" por MCP aplicable; avisos a stderr.
//   same <json>
//       Lee de stdin la salida de `claude mcp get <nombre>` y sale 0 si coincide
//       con la configuracion deseada (tipo, command, args, url).
import { readFileSync } from 'node:fs';
import { parseMachineEnv } from './merge-settings.mjs';

// Sustituye {{CLAVE}} en cada cadena del objeto; devuelve null si falta alguna.
function rellenar(valor, vars) {
  let falta = null;
  const rec = (v) => {
    if (typeof v === 'string') {
      return v.replace(/\{\{([A-Z_]+)\}\}/g, (m, k) => {
        if (vars[k] === undefined) { falta = k; return m; }
        return vars[k];
      });
    }
    if (Array.isArray(v)) return v.map(rec);
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, rec(x)]));
    return v;
  };
  const out = rec(valor);
  return falta ? { falta } : { out };
}

function plan(rutaMcp, rutaEnv, home) {
  const lista = JSON.parse(readFileSync(rutaMcp, 'utf8'));
  const maquina = parseMachineEnv(readFileSync(rutaEnv, 'utf8'));
  const vars = { HOME: home };
  if (maquina.PHPSTORM_URL) vars.PHPSTORM_URL = maquina.PHPSTORM_URL;
  if (maquina.PYCHARM_URL) vars.PYCHARM_URL = maquina.PYCHARM_URL;
  for (const e of lista) {
    if (e.when === 'ide' && maquina.IDE_MCP !== 'yes') continue;
    const r = rellenar(e.config, vars);
    if (r.falta) {
      console.error(`aviso: se omite ${e.name}: falta ${r.falta} en machine.env`);
      continue;
    }
    console.log(`${e.name}\t${JSON.stringify(r.out)}`);
  }
}

function igual(json, texto) {
  const c = JSON.parse(json);
  const campo = (etiqueta) => {
    const m = texto.match(new RegExp(`^\\s*${etiqueta}:[ \\t]*(.*)$`, 'm'));
    return m ? m[1].trim() : null;
  };
  if ((campo('Type') ?? 'stdio') !== (c.type ?? 'stdio')) return false;
  if (c.command !== undefined) {
    return campo('Command') === c.command && (campo('Args') ?? '') === (c.args ?? []).join(' ');
  }
  return campo('URL') === c.url;
}

const [cmd, ...args] = process.argv.slice(2);
try {
  if (cmd === 'plan' && args.length === 3) plan(...args);
  else if (cmd === 'same' && args.length === 1) process.exit(igual(args[0], readFileSync(0, 'utf8')) ? 0 : 1);
  else { console.error('uso: mcp-helper.mjs plan <mcp.json> <machine.env> <home> | same <json>'); process.exit(2); }
} catch (e) {
  console.error(`mcp-helper: ${e.message}`);
  process.exit(2);
}
