#!/bin/sh
# update-versions.sh: reescribe versions.lock con lo que hay instalado en este equipo. POSIX sh.
# Uso: update-versions.sh [--dry-run | --check]
#   (sin opcion)  reescribe versions.lock (archivo temporal + mv).
#   --dry-run     muestra la diferencia contra el versions.lock actual y no escribe nada.
#   --check       sale con 0 si versions.lock ya coincide con lo instalado y con 1 si no;
#                 no escribe nada.
# Lee las versiones con las mismas funciones que doctor.sh (lib/common.sh):
#   codebase-memory-mcp: primer X.Y.Z de `$HOME/.local/bin/codebase-memory-mcp --version`;
#   plugin.<id>: version de <id> en $HOME/.claude/plugins/installed_plugins.json, solo para
#     los plugins con enabledPlugins.<id> = true en $HOME/.claude/settings.json (uno
#     deshabilitado sale de versions.lock).
# El resultado esta ordenado por clave (LC_ALL=C) y termina en salto de linea; las lineas
# vacias y los comentarios del lock actual no se conservan. Si una fuente falta (binario,
# installed_plugins.json, settings.json, o un plugin habilitado que no esta instalado), es un
# aviso y esa clave queda como estaba en el lock: nunca se borra en silencio.
# Solo escribe versions.lock. Codigos: 0 bien (o --check coincide); 1 --check difiere u otro
# fallo; 3 falta node.

case ${HOME:-} in
  /*) [ -d "$HOME" ] || { echo "error: HOME no es una carpeta: $HOME" >&2; exit 1; } ;;
  *) echo "error: HOME debe ser una ruta absoluta (vale '${HOME:-}')" >&2; exit 1 ;;
esac
command -v node >/dev/null 2>&1 || { echo "error: falta node" >&2; exit 3; }
SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
REPO=$SELF_DIR
. "$REPO/lib/common.sh"
MODO=escribir
case ${1:-} in
  "") ;;
  --dry-run) MODO=simular ;;
  --check) MODO=comprobar ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) error "opcion desconocida: $1"; echo "uso: update-versions.sh [--dry-run | --check]" >&2; exit 1 ;;
esac
[ $# -le 1 ] || { error "demasiados argumentos"; exit 1; }

LOCK="$REPO/versions.lock"
BIN="$HOME/.local/bin/codebase-memory-mcp"
PLUG="$HOME/.claude/plugins/installed_plugins.json"
SET="$HOME/.claude/settings.json"
NUEVO=$(mktemp) || exit 1
ORD=$(mktemp) || exit 1
HAB=$(mktemp) || exit 1
LOCKTMP=
trap 'rm -f "$NUEVO" "$ORD" "$HAB" "$LOCKTMP"' EXIT

# --- fuentes ---------------------------------------------------------------------
# BIN_V: version del binario (vacio si no hay). PLUGINS_OK: 1 si se pueden leer los
# plugins instalados. HAB_OK: 1 si se pudo leer la lista de plugins habilitados.
BIN_V=$(version_binario "$BIN"); rc=$?
case $rc in
  0) ;;
  1) aviso "no se puede ejecutar $BIN; codebase-memory-mcp queda como estaba en versions.lock" ;;
  *) aviso "$BIN --version no dio una version reconocible; codebase-memory-mcp queda como estaba en versions.lock" ;;
esac
PLUGINS_OK=1
if [ ! -f "$PLUG" ]; then
  aviso "no existe $PLUG; los plugins quedan como estaban en versions.lock"; PLUGINS_OK=0
fi
HAB_OK=1
if [ ! -f "$SET" ]; then
  aviso "no existe $SET; no se sabe que plugins estan habilitados, los plugins quedan como estaban"; HAB_OK=0
elif ! plugins_habilitados "$SET" > "$HAB"; then
  aviso "no se pudo leer $SET; los plugins quedan como estaban en versions.lock"; HAB_OK=0
fi

# --- clave=valor nuevos (sin ordenar) -----------------------------------------------
: > "$NUEVO"
[ -n "$BIN_V" ] && printf 'codebase-memory-mcp=%s\n' "$BIN_V" >> "$NUEVO"
if [ "$PLUGINS_OK" = 1 ] && [ "$HAB_OK" = 1 ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    inst=$(version_plugin "$PLUG" "$id"); rc=$?
    if [ "$rc" = 3 ]; then aviso "plugin $id: habilitado pero no esta en $PLUG; queda como estaba en versions.lock"
    elif [ "$rc" != 0 ]; then
      aviso "no se pudo leer $PLUG; los plugins quedan como estaban en versions.lock"; break
    else
      set -- $inst
      if [ $# -eq 0 ]; then aviso "plugin $id: sin version en $PLUG; queda como estaba en versions.lock"
      else printf 'plugin.%s=%s\n' "$id" "$1" >> "$NUEVO"
      fi
    fi
  done < "$HAB"
fi

# --- mezcla con el lock actual -------------------------------------------------------
# buscar <clave>: imprime el valor nuevo de la clave en $NUEVO; 1 si no esta.
buscar() {
  while IFS== read -r _k _v; do
    [ "$_k" = "$1" ] && { printf '%s\n' "$_v"; return 0; }
  done < "$NUEVO"
  return 1
}
# Detectadas ($NUEVO) mas, del lock actual, las claves que no se pudieron detectar y que no
# estan deshabilitadas a proposito.
cp "$NUEVO" "$ORD" || exit 1
if [ -f "$LOCK" ]; then
  while IFS== read -r clave valor || [ -n "$clave" ]; do
    case $clave in ""|"#"*) continue ;; esac
    buscar "$clave" >/dev/null && continue
    case $clave in
      plugin.*)
        # Un plugin deshabilitado (settings.json legible y sin el id) sale del lock.
        if [ "$HAB_OK" = 1 ] && ! grep -qxF -- "${clave#plugin.}" "$HAB"; then continue; fi ;;
    esac
    printf '%s=%s\n' "$clave" "$valor" >> "$ORD"
  done < "$LOCK"
fi
LC_ALL=C sort -t= -k1,1 "$ORD" > "$NUEVO" || exit 1

# --- salida ---------------------------------------------------------------------------
IGUAL=0
[ -f "$LOCK" ] && cmp -s "$NUEVO" "$LOCK" && IGUAL=1
case $MODO in
  comprobar)
    if [ "$IGUAL" = 1 ]; then info "versions.lock coincide con lo instalado"; exit 0; fi
    info "versions.lock difiere de lo instalado (use update-versions.sh --dry-run para ver la diferencia)"
    exit 1 ;;
  simular)
    if [ "$IGUAL" = 1 ]; then info "sin cambios: versions.lock ya coincide con lo instalado"; exit 0; fi
    if [ -f "$LOCK" ]; then diff "$LOCK" "$NUEVO" | sed -n '/^[<>]/p' | sed -e 's/^< /-/' -e 's/^> /+/'
    else sed 's/^/+/' "$NUEVO"; fi
    exit 0 ;;
esac
if [ "$IGUAL" = 1 ]; then info "sin cambios: versions.lock ya coincide con lo instalado"; exit 0; fi
LOCKTMP=$(mktemp "$LOCK.XXXXXX") || exit 1
# mktemp crea 0600: conserva el modo del lock actual (o 0644 si no existe).
if [ -f "$LOCK" ]; then cp -p "$LOCK" "$LOCKTMP" || exit 1; else chmod 644 "$LOCKTMP" || exit 1; fi
cat "$NUEVO" > "$LOCKTMP" && mv "$LOCKTMP" "$LOCK" || exit 1
LOCKTMP=
info "versions.lock actualizado"
exit 0
