#!/bin/sh
# doctor.sh: comprueba que este equipo coincide con el repo. POSIX sh. Solo lee: no
# escribe nada salvo en la salida estandar (el settings.json regenerado va a un temporal
# que se borra). Uso: doctor.sh
#
# Comprueba, y lista cada diferencia como "diferencia: ...":
#   - enlaces de ~/.claude/ y ~/.config/git/hooks/: faltan, estan rotos, apuntan a otro
#     sitio, o son archivos normales (se dice si su contenido difiere del repo);
#   - los enlaces del manifiesto (si existe) que ya no son validos;
#   - en modo copia (el manifiesto tiene lineas copia; sin manifiesto, P4_COPY=1 o Windows),
#     en vez de enlaces se comparan las copias con el repo: faltan, son enlaces, difieren
#     (cambios a mano o repo cambiado sin repetir la instalacion) o su origen ya no existe;
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
# Solo se miran las entradas que el repo tiene y las del manifiesto: lo que hay de mas en
# ~/.claude (p. ej. las rutas de adopt-ignore, como skills/synced) no es una diferencia.
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

# --- modo: enlaces o copias ---------------------------------------------------
TIENE_OS=1; detectar_os || TIENE_OS=0
MODO=enlace
if [ -f "$MANIFEST" ]; then
  grep -q "^copia$TAB" "$MANIFEST" && MODO=copia
elif [ "${P4_COPY:-0}" = 1 ] || { [ "$TIENE_OS" = 1 ] && [ "$OS" = windows ]; }; then
  MODO=copia
fi

# revisar_copia <destino> <origen>
revisar_copia() {
  if [ -L "$1" ]; then dif "$1 es un enlace (a $(readlink "$1")); deberia ser una copia de $2"
  elif [ ! -e "$1" ]; then dif "falta la copia $1 (de $2)"
  elif [ ! -e "$2" ]; then dif "la copia $1 ya no tiene origen en el repo ($2)"
  elif ! mismo_contenido "$1" "$2"; then dif "la copia $1 difiere de $2 (cambios a mano, o repita la instalacion)"
  fi
}

# Instalacion de otro clon: un solo mensaje claro en vez de un enlace ajeno por entrada.
if _oc=$(manifiesto_otro_clon "$MANIFEST" "$REPO"); then
  dif "la instalacion es de otro clon (por ejemplo $_oc), no de $REPO; ejecute uninstall.sh desde el clon antiguo, copie machine.env y ejecute install.sh desde este"
fi

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
# Los hooks de git solo se revisan si el manifiesto dice que el instalador los puso
# (si la carpeta tenia contenido ajeno, los omitio a proposito).
GIT_INSTALADOS=0
if [ -f "$MANIFEST" ] && grep -q -e "^link$TAB$GITHOOKS_DIR/" -e "^copia$TAB$GITHOOKS_DIR/" "$MANIFEST"; then GIT_INSTALADOS=1; fi
[ "$GIT_INSTALADOS" = 1 ] || aviso "hooks de git no instalados en este equipo segun el manifiesto; no se revisan"
PARES=$(pares_repo "$REPO" "$CLAUDE_DIR" "$GITHOOKS_DIR")
NL='
'
NL_PARES="$NL$PARES$NL"
while IFS="$TAB" read -r dest orig; do
  [ -n "$dest" ] || continue
  case $dest in "$GITHOOKS_DIR"/*) [ "$GIT_INSTALADOS" = 1 ] || continue ;; esac
  if [ "$MODO" = copia ]; then revisar_copia "$dest" "$orig"; else revisar_enlace "$dest" "$orig"; fi
done <<EOF
$PARES
EOF
if [ -f "$MANIFEST" ]; then
  while IFS="$TAB" read -r kind ruta extra; do
    case $kind in
      link) revisar_enlace "$ruta" "$extra" ;;
      copia)
        # Las que el repo aun tiene ya se revisaron arriba.
        case $NL_PARES in *"$NL$ruta$TAB"*) ;; *) revisar_copia "$ruta" "$extra" ;; esac ;;
    esac
  done < "$MANIFEST"
fi

# --- core.hooksPath -----------------------------------------------------------
hp=$(git config --global --get core.hooksPath 2>/dev/null)
case $hp in "~/"*) hp="$HOME/${hp#"~/"}" ;; esac
[ "$GIT_INSTALADOS" = 0 ] || [ "$hp" = "$GITHOOKS_DIR" ] || dif "core.hooksPath vale '${hp:-(sin fijar)}' y deberia valer $GITHOOKS_DIR"

# --- settings.json ------------------------------------------------------------
if [ "$TIENE_OS" = 0 ]; then
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
      vers=$(version_binario "$BIN"); rc=$?
      if [ "$rc" = 1 ]; then
        aviso "no se puede ejecutar $BIN; no se comprueba la version de $clave"
      elif [ "$rc" = 2 ]; then aviso "$BIN --version no dio una version reconocible"
      elif [ "$vers" != "$valor" ]; then dif "version de $clave: instalada $vers, versions.lock pide $valor"
      fi ;;
    plugin.*)
      id=${clave#plugin.}
      if [ ! -f "$PLUG" ]; then
        [ -n "${AVISO_PLUG:-}" ] || aviso "no existe $PLUG; no se comprueban las versiones de plugins"
        AVISO_PLUG=1
      else
        inst=$(version_plugin "$PLUG" "$id")
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
