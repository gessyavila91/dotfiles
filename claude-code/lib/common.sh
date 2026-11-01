#!/bin/sh
# common.sh: funciones compartidas del instalador (y de uninstall/doctor). POSIX sh.
# Se carga con `. common.sh`. Solo definiciones; no hace nada al cargarse.
#
# Variables que usa (las fija quien carga): HOME, CLAUDE_DIR, DRY (1 = simulacion),
# TS (marca de tiempo AAAAMMDD-HHMMSS de esta ejecucion).
#
# MANIFIESTO: <HOME>/.claude/.p4-manifest, texto, una entrada por linea, sin duplicados
# (se anade por paso, asi una instalacion interrumpida y repetida converge al mismo
# archivo). Formato:
#   kind<TAB>path<TAB>extra
# con kind:
#   dir       carpeta creada por el instalador (extra vacio). Se anota la carpeta
#             mas externa primero; uninstall la quita solo si queda vacia.
#   link      enlace simbolico creado; extra = destino (archivo del clon).
#   settings  settings.json generado (archivo normal, nunca enlace); extra = "generado".
#   gitconfig clave de git global fijada por el instalador; path = clave
#             (core.hooksPath), extra = valor.
#   adopt     archivo o carpeta copiado al clon con --adopt; path = ruta en el clon,
#             extra = ruta de origen en HOME.
# y ademas lineas
#   backup=<dir>
# una por cada carpeta de respaldo creada (la ultima es la mas reciente).

TAB=$(printf '\t')

info() { printf '%s\n' "$*"; }
aviso() { printf 'aviso: %s\n' "$*" >&2; }
error() { printf 'error: %s\n' "$*" >&2; }

# hacer <descripcion>: anuncia la accion. En simulacion devuelve 1 (no ejecutar).
hacer() {
  if [ "${DRY:-0}" = 1 ]; then
    printf 'simulacion: %s\n' "$1"
    return 1
  fi
  printf '%s\n' "$1"
  return 0
}

# manifiesto_add <linea>: anade la linea si no esta. Nada en simulacion.
manifiesto_add() {
  [ "${DRY:-0}" = 1 ] && return 0
  _m="$CLAUDE_DIR/.p4-manifest"
  [ -d "$CLAUDE_DIR" ] || return 0
  if [ -f "$_m" ] && grep -qxF -- "$1" "$_m"; then return 0; fi
  printf '%s\n' "$1" >> "$_m"
}

# asegurar_dir <dir>: crea la carpeta (y las de arriba) anotando cada una en el manifiesto.
# La carpeta de CLAUDE_DIR se anota despues de crearla, cuando el manifiesto ya cabe.
asegurar_dir() {
  [ -d "$1" ] && return 0
  asegurar_dir "$(dirname "$1")" || return 1
  hacer "crear carpeta $1" || return 0
  mkdir "$1" || return 1
  manifiesto_add "dir$TAB$1$TAB"
}

# es_nuestro <destino> <origen>: 0 si destino es un enlace que apunta a origen
# (origen es ruta fisica; se admite un destino relativo o con otra forma de la ruta).
es_nuestro() {
  [ -L "$1" ] || return 1
  _t=$(readlink "$1") || return 1
  [ "$_t" = "$2" ] && return 0
  case $_t in /*) ;; *) _t="$(dirname "$1")/$_t" ;; esac
  _d=$(cd "$(dirname "$_t")" 2>/dev/null && pwd -P) || return 1
  [ "$_d/$(basename "$_t")" = "$2" ]
}

# mismo_contenido <a> <b>: 0 si archivos o carpetas tienen el mismo contenido.
mismo_contenido() {
  [ -e "$1" ] && [ -e "$2" ] && diff -r "$1" "$2" >/dev/null 2>&1
}

# respaldo_dir: crea (una sola vez por ejecucion) la carpeta de respaldo
# $HOME/Respaldos/p4-AAAAMMDD-HHMMSS-XXXXXX con permisos 700 y la deja en RESPALDO.
# El instalador nunca la borra.
respaldo_dir() {
  [ -n "${RESPALDO:-}" ] && return 0
  mkdir -p "$HOME/Respaldos" || return 1
  RESPALDO=$(mktemp -d "$HOME/Respaldos/p4-$TS-XXXXXX") || return 1
  chmod 700 "$RESPALDO" || return 1
  info "respaldo en $RESPALDO"
  manifiesto_add "backup=$RESPALDO"
}

# respaldar_mover <ruta>: mueve la ruta (archivo, carpeta o enlace) al respaldo,
# conservando su ruta relativa a HOME.
respaldar_mover() {
  respaldo_dir || return 1
  _rel=${1#"$HOME"/}
  mkdir -p "$RESPALDO/$(dirname "$_rel")" || return 1
  mv "$1" "$RESPALDO/$_rel"
}

# ruta_resuelta <ruta>: ruta fisica (cd -P) de la carpeta existente mas cercana,
# seguida del resto de la ruta que aun no existe.
ruta_resuelta() {
  _r=$1; _resto=
  while [ ! -d "$_r" ]; do
    _resto="/${_r##*/}$_resto"
    _r=$(dirname "$_r")
  done
  printf '%s%s\n' "$(cd -P "$_r" && pwd -P)" "$_resto"
}
