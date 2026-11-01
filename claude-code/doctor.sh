#!/bin/sh
# doctor.sh: comprueba que este equipo coincide con el repo. POSIX sh. Solo lee: no
# escribe nada salvo en la salida estandar (el settings.json regenerado va a un temporal
# que se borra). Uso: doctor.sh
#
# Comprueba, y lista cada diferencia como "diferencia: ...":
#   - enlaces de ~/.claude/ y ~/.config/git/hooks/: faltan, estan rotos, apuntan a otro
#     sitio, o son archivos normales (se dice si su contenido difiere del repo);
#   - los enlaces del manifiesto (si existe) que ya no son validos;
#   - core.hooksPath distinto de ~/.config/git/hooks;
#   - settings.json distinto del regenerado con merge-settings.mjs (mismos --os, --home y
#     machine.env; sin machine.env se usa machine.env.example y se avisa);
#   - versions.lock contra lo instalado:
#       codebase-memory-mcp: se ejecuta $HOME/.local/bin/codebase-memory-mcp --version y se
#         toma el primer numero X.Y.Z de su salida;
#       plugin.<id>: se busca <id> en $HOME/.claude/plugins/installed_plugins.json
#         (plugins.<id>[].version); un plugin ausente de ese archivo es una diferencia;
#   - MCP de mcp.json (los que aplican segun machine.env) contra `claude mcp list`
#     (una linea "nombre: ..." por MCP registrado).
# Una fuente que no existe o no se puede ejecutar (binario, installed_plugins.json, claude)
# es un aviso en stderr, no una diferencia.
# Codigos: 0 todo coincide; 1 hay diferencias; 3 falta node.

case ${HOME:-} in
  /*) [ -d "$HOME" ] || { echo "error: HOME no es una carpeta: $HOME" >&2; exit 1; } ;;
  *) echo "error: HOME debe ser una ruta absoluta (vale '${HOME:-}')" >&2; exit 1 ;;
esac
SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
REPO=$SELF_DIR
. "$REPO/lib/common.sh"
case ${1:-} in
  "") ;;
  -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) error "opcion desconocida: $1"; echo "uso: doctor.sh" >&2; exit 1 ;;
esac

command -v node >/dev/null 2>&1 || { error "falta node"; exit 3; }
CLAUDE_DIR="$HOME/.claude"
GITHOOKS_DIR="$HOME/.config/git/hooks"
MANIFEST="$CLAUDE_DIR/.p4-manifest"
DIFS=$(mktemp) || exit 1
SET_TMP=$(mktemp) || exit 1
trap 'rm -f "$DIFS" "$SET_TMP"' EXIT
dif() { printf 'diferencia: %s\n' "$*" >> "$DIFS"; }

# --- enlaces -----------------------------------------------------------------
# revisar_enlace <destino> <origen esperado o vacio>
revisar_enlace() {
  _d=$1; _o=$2
  if [ -L "$_d" ]; then
    if [ ! -e "$_d" ]; then
      dif "enlace roto: $_d -> $(readlink "$_d")"
    elif [ -n "$_o" ] && ! es_nuestro "$_d" "$_o"; then
      dif "enlace ajeno: $_d apunta a $(readlink "$_d") y deberia apuntar a $_o"
    fi
  elif [ -e "$_d" ]; then
    if [ -n "$_o" ] && mismo_contenido "$_d" "$_o"; then
      dif "$_d es una copia, no un enlace a $_o (mismo contenido)"
    elif [ -n "$_o" ]; then
      dif "$_d es una copia, no un enlace a $_o, y su contenido difiere"
    fi
  elif [ -n "$_o" ]; then
    dif "falta el enlace $_d (deberia apuntar a $_o)"
  fi
}
PARES=$(pares_repo "$REPO" "$CLAUDE_DIR" "$GITHOOKS_DIR")
while IFS="$TAB" read -r dest orig; do
  [ -n "$dest" ] && revisar_enlace "$dest" "$orig"
done <<EOF
$PARES
EOF
if [ -f "$MANIFEST" ]; then
  while IFS="$TAB" read -r kind ruta extra; do
    [ "$kind" = link ] && revisar_enlace "$ruta" "$extra"
  done < "$MANIFEST"
fi

# --- core.hooksPath -----------------------------------------------------------
hp=$(git config --global --get core.hooksPath 2>/dev/null)
case $hp in "~/"*) hp="$HOME/${hp#"~/"}" ;; esac
[ "$hp" = "$GITHOOKS_DIR" ] || dif "core.hooksPath vale '${hp:-(sin fijar)}' y deberia valer $GITHOOKS_DIR"

# --- settings.json ------------------------------------------------------------
if ! detectar_os; then
  aviso "sistema no soportado ($(uname -s)); se omite la comprobacion de settings.json"
elif ! settings_regenerar "$REPO" "$OS" "$SET_TMP"; then
  dif "no se pudo regenerar settings.json con merge-settings.mjs"
else
  [ "$SETTINGS_SIN_MACHINE" = 1 ] && aviso "no hay machine.env; se regenera con machine.env.example"
  SET="$CLAUDE_DIR/settings.json"
  if [ -L "$SET" ]; then dif "$SET es un enlace; deberia ser un archivo generado"
  elif [ ! -f "$SET" ]; then dif "falta $SET"
  elif ! cmp -s "$SET_TMP" "$SET"; then
    dif "$SET difiere del regenerado (lineas '<' = esperado, '>' = actual):"
    diff "$SET_TMP" "$SET" | sed -n '/^[<>]/p' | head -10 | sed 's/^/    /' >> "$DIFS"
  fi
fi

# --- versiones (versions.lock) --------------------------------------------------
BIN="$HOME/.local/bin/codebase-memory-mcp"
PLUG="$CLAUDE_DIR/plugins/installed_plugins.json"
while IFS== read -r clave valor; do
  case $clave in
    ""|"#"*) continue ;;
    codebase-memory-mcp)
      if [ ! -x "$BIN" ]; then
        aviso "no se puede ejecutar $BIN; no se comprueba la version de $clave"
      else
        salida=$("$BIN" --version 2>&1 </dev/null | head -5)
        # Primer X.Y.Z de cada linea ("... 0.9.0 (go1.22.3)" da 0.9.0).
        vers=$(printf '%s\n' "$salida" | sed -n ':a
s/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/
t f
s/^[^0-9]*[0-9][0-9]*//
t a
d
:f
p' | head -1)
        if [ -z "$vers" ]; then aviso "$BIN --version no dio una version reconocible"
        elif [ "$vers" != "$valor" ]; then dif "version de $clave: instalada $vers, versions.lock pide $valor"
        fi
      fi ;;
    plugin.*)
      id=${clave#plugin.}
      if [ ! -f "$PLUG" ]; then
        [ -n "${AVISO_PLUG:-}" ] || aviso "no existe $PLUG; no se comprueban las versiones de plugins"
        AVISO_PLUG=1
      else
        inst=$(node -e '
          const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
          const e = (j.plugins || {})[process.argv[2]];
          if (e === undefined) process.exit(3);
          const l = Array.isArray(e) ? e : [e];
          console.log(l.map((x) => x.version).filter(Boolean).join(" "));' "$PLUG" "$id" 2>/dev/null)
        rc=$?
        if [ "$rc" = 3 ]; then dif "plugin $id: no esta instalado (versions.lock pide $valor)"
        elif [ "$rc" != 0 ]; then aviso "no se pudo leer $PLUG"
        else
          encontrado=0
          for v in $inst; do [ "$v" = "$valor" ] && encontrado=1; done
          [ "$encontrado" = 1 ] || dif "plugin $id: instalada ${inst:-(sin version)}, versions.lock pide $valor"
        fi
      fi ;;
  esac
done < "$REPO/versions.lock"

# --- MCP registrados ------------------------------------------------------------
# tiene_mcp <nombre>: 0 si alguna linea de $lista empieza por "nombre:" (comparacion literal).
tiene_mcp() {
  while IFS= read -r _l; do
    case $_l in "$1":*) return 0 ;; esac
  done <<EOF
$lista
EOF
  return 1
}
MENV="$REPO/machine.env"; [ -f "$MENV" ] || MENV="$REPO/machine.env.example"
if ! command -v claude >/dev/null 2>&1; then
  aviso "no se encontro 'claude'; no se comprueban los MCP"
elif ! lista=$(claude mcp list </dev/null 2>/dev/null); then
  aviso "'claude mcp list' fallo; no se comprueban los MCP"
else
  esperados=$(node "$REPO/lib/mcp-helper.mjs" plan "$REPO/mcp.json" "$MENV" "$HOME" 2>/dev/null | cut -f1)
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    tiene_mcp "$n" || dif "MCP '$n' no esta registrado (claude mcp list)"
  done <<EOF
$esperados
EOF
fi

# --- resultado --------------------------------------------------------------------
if [ -s "$DIFS" ]; then
  cat "$DIFS"
  printf '%s diferencia(s) entre este equipo y el repo\n' "$(grep -c '^diferencia:' "$DIFS")"
  exit 1
fi
info "sin diferencias: el equipo coincide con el repo"
exit 0
