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
#   copia     archivo o carpeta copiado (modo copia, --copy o P4_COPY=1; Windows);
#             extra = origen en el clon. El manifiesto es lo que la hace "nuestra":
#             se anota antes de escribirla. Una instalacion usa enlaces o copias, no ambos.
#   settings  settings.json (archivo normal, nunca enlace); extra = "generado" (lo escribio el
#             instalador) o "preexistente" (ya existia identico al generado; uninstall no
#             lo borra). Una sola linea: la primera instalacion decide.
#   gitconfig clave de git global fijada por el instalador; path = clave
#             (core.hooksPath), extra = valor.
#   adopt     archivo o carpeta copiado al clon con --adopt; path = ruta en el clon,
#             extra = ruta de origen en HOME.
# y ademas lineas
#   backup=<dir>
# una por cada carpeta de respaldo creada (la ultima es la mas reciente).
# Dentro de un respaldo, p4-copias-previas/<ruta relativa a HOME> guarda copias nuestras
# que se sustituyeron al actualizar (modo copia); uninstall no las restaura.

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
  _en_t=$(readlink "$1") || return 1
  [ "$_en_t" = "$2" ] && return 0
  case $_en_t in /*) ;; *) _en_t="$(dirname "$1")/$_en_t" ;; esac
  _en_d=$(cd "$(dirname "$_en_t")" 2>/dev/null && pwd -P) || return 1
  [ "$_en_d/$(basename "$_en_t")" = "$2" ]
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

# detectar_os: fija OS (macos|linux|windows) segun uname; devuelve 1 si no se soporta.
# En Windows solo se admite Git Bash (MINGW/MSYS) o Cygwin.
detectar_os() {
  case $(uname -s) in
    Darwin) OS=macos ;;
    Linux) OS=linux ;;
    MINGW*|MSYS*|CYGWIN*) OS=windows ;;
    *) return 1 ;;
  esac
}

# manifiesto_copia <manifiesto> <destino>: imprime el origen anotado en la linea "copia"
# de <destino>; devuelve 1 si no hay ninguna.
manifiesto_copia() {
  [ -f "$1" ] || return 1
  while IFS="$TAB" read -r _mc_k _mc_p _mc_e; do
    if [ "$_mc_k" = copia ] && [ "$_mc_p" = "$2" ]; then printf '%s\n' "$_mc_e"; return 0; fi
  done < "$1"
  return 1
}

# copia_nuestra <manifiesto> <destino> <origen>: 0 si <destino> existe, no es un enlace y el
# manifiesto lo anota como copia de <origen> (el contenido puede diferir).
copia_nuestra() {
  [ -e "$2" ] && [ ! -L "$2" ] || return 1
  _cn=$(manifiesto_copia "$1" "$2") || return 1
  [ "$_cn" = "$3" ]
}

# respaldar_copia_previa <ruta>: mueve una copia nuestra que se va a sustituir a
# <respaldo>/p4-copias-previas/<ruta relativa a HOME> (uninstall no la restaura).
respaldar_copia_previa() {
  respaldo_dir || return 1
  _rcp=${1#"$HOME"/}
  mkdir -p "$RESPALDO/p4-copias-previas/$(dirname "$_rcp")" || return 1
  mv "$1" "$RESPALDO/p4-copias-previas/$_rcp"
}

# settings_regenerar <repo> <os> <salida>: genera el settings.json que produciria el
# instalador (mismos --os, --home y machine.env). Sin machine.env usa machine.env.example
# y deja SETTINGS_SIN_MACHINE=1. Devuelve el codigo de node.
settings_regenerar() {
  _sr_menv="$1/machine.env"; SETTINGS_SIN_MACHINE=0
  if [ ! -f "$_sr_menv" ]; then _sr_menv="$1/machine.env.example"; SETTINGS_SIN_MACHINE=1; fi
  node "$1/lib/merge-settings.mjs" --dir "$1" --os "$2" --machine "$_sr_menv" \
    --home "$HOME" --out "$3"
}

# enlace_al_repo <ruta> <repo>: 0 si es un enlace cuyo destino (absoluto, o relativo
# al enlace) queda dentro de <repo>.
enlace_al_repo() {
  [ -L "$1" ] || return 1
  _er_t=$(readlink "$1") || return 1
  case $_er_t in /*) ;; *) _er_t="$(dirname "$1")/$_er_t" ;; esac
  case $_er_t in "$2"/*) return 0 ;; *) return 1 ;; esac
}

# pares_repo <repo> <claude_dir> <githooks_dir>: "destino<TAB>origen" de todo lo que el
# instalador enlaza, segun lo que el repo contiene hoy (sin --adopt).
pares_repo() {
  printf '%s\t%s\n' "$2/CLAUDE.md" "$1/CLAUDE.md"
  for _pr_sub in skills hooks themes; do
    for _pr_o in "$1/$_pr_sub"/*; do
      [ -e "$_pr_o" ] || continue
      printf '%s\t%s\n' "$2/$_pr_sub/${_pr_o##*/}" "$_pr_o"
    done
  done
  while IFS= read -r _pr_n; do
    [ -n "$_pr_n" ] && printf '%s\t%s\n' "$3/$_pr_n" "$1/git-hooks/dispatch"
  done < "$1/git-hooks/NAMES"
  printf '%s\t%s\n' "$3/lib.sh" "$1/git-hooks/lib.sh"
}

# normalizar_home <archivo>: imprime el archivo cambiando cada "<HOME>/" literal (el
# home real de esta ejecucion) por la cadena "$HOME/". Es la misma normalizacion que
# usa tests/test-content.sh para comparar la copia del repo con el original.
normalizar_home() {
  _h=$(printf '%s\n' "$HOME" | sed 's/[][\.*^$|]/\\&/g')
  sed "s|$_h/|\$HOME/|g" "$1"
}

# equivalente_home <destino> <origen>: 0 si destino y origen (archivos o carpetas)
# solo difieren en que el destino lleva el home literal donde el origen lleva "$HOME/".
# Las demas diferencias (incluidos archivos de mas o de menos) no son equivalentes.
equivalente_home() {
  [ -e "$1" ] && [ -e "$2" ] || return 1
  _eq=$(mktemp -d) || return 1
  if [ -d "$1" ]; then cp -R "$1" "$_eq/x" || { rm -rf "$_eq"; return 1; }
  else cp "$1" "$_eq/x" || { rm -rf "$_eq"; return 1; }
  fi
  find "$_eq/x" -type f | while IFS= read -r _f; do
    normalizar_home "$_f" > "$_f.p4n" && mv "$_f.p4n" "$_f"
  done
  diff -r "$_eq/x" "$2" >/dev/null 2>&1; _rc=$?
  rm -rf "$_eq"
  return $_rc
}

# en_adopt_ignore <repo> <ruta>: 0 si <ruta> (relativa a ~/.claude, p. ej. skills/synced)
# figura tal cual en <repo>/adopt-ignore. Comparacion literal, sin comodines; se saltan
# las lineas vacias y las que empiezan por #.
en_adopt_ignore() {
  [ -f "$1/adopt-ignore" ] || return 1
  while IFS= read -r _ai || [ -n "$_ai" ]; do
    case $_ai in ""|"#"*) continue ;; esac
    [ "$_ai" = "$2" ] && return 0
  done < "$1/adopt-ignore"
  return 1
}
