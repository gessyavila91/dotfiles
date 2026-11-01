#!/bin/sh
# mcp-register.sh: registra los MCP de usuario con la CLI de Claude. POSIX sh.
# Se carga con `. mcp-register.sh` y se llama:  mcp_register <mcp.json> <machine.env> <os>
#
# Idempotencia: por cada MCP se ejecuta `claude mcp get <nombre>`; si existe y su
# tipo, comando, argumentos o URL coinciden con lo deseado, no se hace nada. Si no
# existe o difiere, `claude mcp add-json --scope user <nombre> '<json>'` (para un
# nombre existente se quita antes con `claude mcp remove --scope user`).
# Sin `claude` en el PATH avisa y sale con 0.

# En POSIX sh un script cargado con `.` no puede saber su propia ruta: quien lo carga
# define MCP_REGISTER_DIR (carpeta lib/); si no, se asume la de $0.
_MCP_LIB=${MCP_REGISTER_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}

mcp_register() {
  _mcp_json=$1; _mcp_env=$2; _mcp_os=$3
  if [ $# -ne 3 ]; then
    echo "uso: mcp_register <mcp.json> <machine.env> <os>" >&2
    return 2
  fi
  case $_mcp_os in
    macos|linux|windows) ;;
    *) echo "mcp-register: sistema desconocido: $_mcp_os" >&2; return 2 ;;
  esac
  if [ ! -f "$_MCP_LIB/mcp-helper.mjs" ]; then
    echo "mcp-register: defina MCP_REGISTER_DIR (carpeta lib/ con mcp-helper.mjs)" >&2
    return 1
  fi
  if ! command -v claude >/dev/null 2>&1; then
    echo "aviso: no se encontro 'claude' en el PATH; MCP sin registrar (volver a ejecutar tras instalarlo)" >&2
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "mcp-register: falta node" >&2
    return 1
  fi
  _mcp_plan=$(node "$_MCP_LIB/mcp-helper.mjs" plan "$_mcp_json" "$_mcp_env" "$HOME") || return 1
  [ -n "$_mcp_plan" ] || return 0
  _mcp_tab=$(printf '\t')
  _mcp_rc=0
  printf '%s\n' "$_mcp_plan" | while IFS= read -r _mcp_line; do
    _mcp_name=${_mcp_line%%"$_mcp_tab"*}
    _mcp_cfg=${_mcp_line#*"$_mcp_tab"}
    if _mcp_actual=$(claude mcp get "$_mcp_name" 2>/dev/null); then
      if printf '%s\n' "$_mcp_actual" | node "$_MCP_LIB/mcp-helper.mjs" same "$_mcp_cfg"; then
        echo "mcp: $_mcp_name ya registrado"
        continue
      fi
      claude mcp remove --scope user "$_mcp_name" >/dev/null 2>&1
    fi
    if claude mcp add-json --scope user "$_mcp_name" "$_mcp_cfg" >/dev/null; then
      echo "mcp: $_mcp_name registrado"
    else
      echo "mcp: fallo al registrar $_mcp_name" >&2
      exit 1
    fi
  done || _mcp_rc=1
  return $_mcp_rc
}
