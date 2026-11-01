#!/bin/sh
# install.sh: instala la configuracion de Claude Code de este clon en $HOME (macOS y Linux).
# POSIX sh. Uso: install.sh [--dry-run] [--adopt] [--non-interactive]
#
# Codigos de salida: 0 bien; 2 hay destinos ajenos (sin --adopt, o con --adopt y el
# repo ya tiene una version distinta; o, con o sin --adopt, ~/.claude, sus carpetas
# skills/hooks/themes o ~/.config/git/hooks son enlaces simbolicos o resuelven dentro
# del clon o fuera de HOME); 3 falta un requisito (node o git) o el sistema
# no es macOS ni Linux; 1 cualquier otro fallo (p. ej. HOME vacio o relativo).
#
# Pasos (cada uno idempotente; el manifiesto se anota por paso, asi que volver a
# ejecutar tras una interrupcion converge al mismo estado):
#   requisitos -> analisis (no escribe nada) -> machine -> enlaces -> githooks
#   -> settings -> mcp
#
# El clon es la carpeta que contiene este script; los enlaces apuntan a el. Destino:
# $HOME/.claude/ y $HOME/.config/git/hooks/. Formato del manifiesto: lib/common.sh.
#
# --adopt (seccion 7, paso 3 del diseno), por cada destino que existe y no es nuestro:
#   - si el repo no tiene ese archivo o carpeta: se copia al repo (la usuaria lo
#     commitea despues), se respalda el original y se pone el enlace;
#   - si el repo lo tiene con el mismo contenido, o solo difiere en que el destino lleva
#     el home real literal donde el repo lleva "$HOME/" (normalizar_home): se respalda
#     y se pone el enlace (gana la version del repo);
#   - si el repo lo tiene y difiere: se muestra la diferencia y se sale con 2 sin
#     tocar nada (no se sobrescribe ningun lado en silencio).
#   Solo se adoptan entradas sin enlaces simbolicos dentro (p. ej. no hooks/peon-ping).
#   Las rutas listadas en adopt-ignore (relativas a ~/.claude, literales) que el repo no
#   tiene no se adoptan, respaldan ni enlazan, y no son conflicto: "ignorado: <ruta>".
#
# P4_FAIL_AFTER=<paso> (SOLO PARA PRUEBAS): termina con 1 justo despues del paso
# indicado, para comprobar que repetir la instalacion converge.

case ${HOME:-} in
  /*) [ -d "$HOME" ] || { echo "error: HOME no es una carpeta: $HOME" >&2; exit 1; } ;;
  *) echo "error: HOME debe ser una ruta absoluta (vale '${HOME:-}')" >&2; exit 1 ;;
esac
SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
REPO=$SELF_DIR
. "$REPO/lib/common.sh"

DRY=0; ADOPT=0; NONINT=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --adopt) ADOPT=1 ;;
    --non-interactive) NONINT=1 ;;
    -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) error "opcion desconocida: $a"; echo "uso: install.sh [--dry-run] [--adopt] [--non-interactive]" >&2; exit 1 ;;
  esac
done

CLAUDE_DIR="$HOME/.claude"
GITHOOKS_DIR="$HOME/.config/git/hooks"
MACHINE_ENV="$REPO/machine.env"
TS=$(date +%Y%m%d-%H%M%S)
RESPALDO=
PLAN=$(mktemp) || exit 1
SET_TMP=$(mktemp) || exit 1
MENV_TMP=
trap 'rm -f "$PLAN" "$SET_TMP" ${MENV_TMP:+"$MENV_TMP"}' EXIT
[ "$DRY" = 1 ] && info "modo simulacion: no se escribe nada"

paso() {
  if [ "${P4_FAIL_AFTER:-}" = "$1" ]; then
    error "fallo forzado tras el paso '$1' (P4_FAIL_AFTER, solo pruebas)"
    exit 1
  fi
}

# --- requisitos ------------------------------------------------------------
for c in git node; do
  if ! command -v "$c" >/dev/null 2>&1; then
    error "falta '$c'; instalelo y vuelva a ejecutar"
    exit 3
  fi
done
command -v claude >/dev/null 2>&1 || aviso "no se encontro 'claude'; los MCP no se registraran"
command -v docker >/dev/null 2>&1 || aviso "no se encontro 'docker'; MCP_DOCKER no funcionara hasta instalarlo"
case $(uname -s) in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  *) error "sistema no soportado: $(uname -s) (en Windows use install.ps1)"; exit 3 ;;
esac
paso requisitos

# --- analisis: que enlazar y que conflictos hay (no escribe nada) ----------
# pares: "destino<TAB>origen" de todo lo que se enlaza en ~/.claude/.
pares() {
  printf '%s\t%s\n' "$CLAUDE_DIR/CLAUDE.md" "$REPO/CLAUDE.md"
  for sub in skills hooks themes; do
    for o in "$REPO/$sub"/*; do
      [ -e "$o" ] || continue
      printf '%s\t%s\n' "$CLAUDE_DIR/$sub/${o##*/}" "$o"
    done
    # Con --adopt, tambien lo que hay en ~/.claude/<sub>/ y el repo no tiene.
    [ "$ADOPT" = 1 ] || continue
    for d in "$CLAUDE_DIR/$sub"/*; do
      [ -e "$d" ] || [ -L "$d" ] || continue
      [ -e "$REPO/$sub/${d##*/}" ] && continue
      # adopt-ignore: solo afecta a entradas que el repo no tiene (las del repo siguen
      # el camino normal). Se anota como linea especial para informarlo fuera.
      if en_adopt_ignore "$REPO" "$sub/${d##*/}"; then
        printf '#ignorado\t%s\n' "$sub/${d##*/}"
        continue
      fi
      if [ -L "$d" ] || find "$d" -type l 2>/dev/null | grep -q .; then
        aviso "no se adopta $d: es o contiene enlaces simbolicos (tratar a mano)"
        continue
      fi
      printf '%s\t%s\n' "$d" "$REPO/$sub/${d##*/}"
    done
  done
}

mostrar_diferencia() { # destino origen
  if [ -L "$1" ]; then
    info "  $1 es un enlace a $(readlink "$1")"
  fi
  if [ -e "$2" ] && [ -e "$1" ]; then
    diff -ru "$2" "$1"
  elif [ -e "$1" ]; then
    info "  (el repo no tiene $2)"
  fi
}

CONFLICTO=0
# Carpetas contenedoras: si alguna es un enlace simbolico, no es una carpeta, o resuelve
# (cd -P, por un enlace en ella o en una carpeta de arriba) dentro del clon o fuera de
# HOME, escribir en ella tocaria el repo o algo ajeno. Es conflicto incluso con --adopt.
HOME_FISICO=$(cd -P "$HOME" && pwd -P) || { error "no se puede entrar en HOME ($HOME)"; exit 1; }
for c in "$CLAUDE_DIR" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/themes" "$GITHOOKS_DIR"; do
  motivo=
  if [ -L "$c" ]; then
    motivo="es un enlace simbolico (a $(readlink "$c"))"
  elif [ -e "$c" ] && [ ! -d "$c" ]; then
    motivo="existe y no es una carpeta"
  else
    r=$(ruta_resuelta "$c")
    case $r in
      "$REPO"|"$REPO"/*) motivo="resuelve dentro del clon ($r)" ;;
      "$HOME_FISICO"/*) ;;
      *) motivo="resuelve fuera de HOME ($r)" ;;
    esac
  fi
  if [ -n "$motivo" ]; then
    error "$c $motivo; resuelvalo a mano (--adopt no lo arregla)"
    CONFLICTO=2
  fi
done
LISTA=
[ "$CONFLICTO" = 0 ] && LISTA=$(pares)
while IFS="$TAB" read -r dest orig; do
  [ -n "$dest" ] || continue
  if [ "$dest" = "#ignorado" ]; then info "ignorado: $orig (adopt-ignore)"; continue; fi
  if es_nuestro "$dest" "$orig"; then
    printf 'ok\t%s\t%s\n' "$dest" "$orig" >> "$PLAN"
  elif [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    printf 'crear\t%s\t%s\n' "$dest" "$orig" >> "$PLAN"
  elif [ "$ADOPT" = 0 ]; then
    if ! mismo_contenido "$dest" "$orig" && equivalente_home "$dest" "$orig"; then
      info "conflicto: $dest existe y no es de este repo; la unica diferencia es la ruta del home (literal en el destino, \$HOME en el repo); --adopt lo resuelve"
    else
      info "conflicto: $dest existe y no es de este repo"
      mostrar_diferencia "$dest" "$orig"
    fi
    CONFLICTO=1
  elif [ ! -e "$orig" ]; then
    printf 'adoptar-nuevo\t%s\t%s\n' "$dest" "$orig" >> "$PLAN"
  elif mismo_contenido "$dest" "$orig"; then
    printf 'adoptar-igual\t%s\t%s\n' "$dest" "$orig" >> "$PLAN"
  elif equivalente_home "$dest" "$orig"; then
    # Solo difiere en el home literal: gana la version del repo (parametrizada).
    info "$dest solo difiere en la ruta del home; se adopta la version del repo"
    printf 'adoptar-igual\t%s\t%s\n' "$dest" "$orig" >> "$PLAN"
  else
    info "conflicto: $dest difiere de la version del repo ($orig); no se adopta"
    mostrar_diferencia "$dest" "$orig"
    CONFLICTO=1
  fi
done <<EOF
$LISTA
EOF
if [ "$CONFLICTO" = 2 ]; then
  error "hay carpetas de destino que no son carpetas normales dentro de HOME; no se toca nada"
  exit 2
fi
if [ "$CONFLICTO" = 1 ]; then
  if [ "$ADOPT" = 1 ]; then
    error "hay destinos distintos de la version del repo; unifique el contenido y repita"
  else
    error "hay destinos que no son de este repo; revise las diferencias o use --adopt"
  fi
  exit 2
fi
paso analisis

# --- machine.env -----------------------------------------------------------
MENV=$MACHINE_ENV
if [ ! -f "$MACHINE_ENV" ]; then
  ide=no
  if [ "$NONINT" = 0 ] && [ "$DRY" = 0 ]; then
    printf '¿Este equipo registra los MCP de IDE (phpstorm, pycharm)? [s/N] '
    read -r r || r=
    case $r in s|S|si|Si|SI|y|Y|yes) ide=yes ;; esac
  fi
  if [ "$DRY" = 1 ]; then
    info "simulacion: crear $MACHINE_ENV desde machine.env.example con IDE_MCP=$ide"
    MENV_TMP=$(mktemp) || exit 1
    sed "s/^IDE_MCP=.*/IDE_MCP=$ide/" "$REPO/machine.env.example" > "$MENV_TMP" || exit 1
    MENV=$MENV_TMP
  else
    sed "s/^IDE_MCP=.*/IDE_MCP=$ide/" "$REPO/machine.env.example" > "$MACHINE_ENV.tmp" \
      && mv "$MACHINE_ENV.tmp" "$MACHINE_ENV" || { error "no se pudo crear $MACHINE_ENV"; exit 1; }
    if [ "$NONINT" = 1 ]; then
      info "creado $MACHINE_ENV con valores por defecto (IDE_MCP=no); editelo si hace falta"
    else
      info "creado $MACHINE_ENV con IDE_MCP=$ide"
    fi
  fi
fi
paso machine

# --- enlaces en ~/.claude/ -------------------------------------------------
while IFS="$TAB" read -r acc dest orig; do
  case $acc in
    ok) manifiesto_add "link$TAB$dest$TAB$orig"; continue ;;
    adoptar-nuevo)
      if hacer "adoptar $dest: copiar al repo en $orig (commitearlo despues)"; then
        cp -Rp "$dest" "$orig" || { error "no se pudo copiar $dest al repo"; exit 1; }
        manifiesto_add "adopt$TAB$orig$TAB$dest"
      fi ;;
  esac
  case $acc in
    adoptar-nuevo|adoptar-igual)
      if hacer "respaldar $dest"; then
        respaldar_mover "$dest" || { error "no se pudo respaldar $dest"; exit 1; }
      fi ;;
  esac
  asegurar_dir "$(dirname "$dest")" || { error "no se pudo crear $(dirname "$dest")"; exit 1; }
  if hacer "enlazar $dest -> $orig"; then
    ln -s "$orig" "$dest" || { error "no se pudo enlazar $dest"; exit 1; }
    manifiesto_add "link$TAB$dest$TAB$orig"
  fi
done < "$PLAN"
paso enlaces

# --- hooks globales de git -------------------------------------------------
origen_githook() { # nombre -> origen en el repo, o vacio si no es nuestro
  if [ "$1" = lib.sh ]; then printf '%s\n' "$REPO/git-hooks/lib.sh"
  elif grep -qxF -- "$1" "$REPO/git-hooks/NAMES"; then printf '%s\n' "$REPO/git-hooks/dispatch"
  fi
}
ajeno=
if [ -e "$GITHOOKS_DIR" ] && [ ! -d "$GITHOOKS_DIR" ]; then
  ajeno=$GITHOOKS_DIR
elif [ -d "$GITHOOKS_DIR" ]; then
  for e in "$GITHOOKS_DIR"/* "$GITHOOKS_DIR"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    o=$(origen_githook "${e##*/}")
    if [ -z "$o" ] || ! es_nuestro "$e" "$o"; then ajeno=$e; break; fi
  done
fi
if [ -n "$ajeno" ]; then
  aviso "$GITHOOKS_DIR tiene contenido ajeno ($ajeno); no se instalan los hooks de git ni se fija core.hooksPath"
else
  asegurar_dir "$GITHOOKS_DIR" || { error "no se pudo crear $GITHOOKS_DIR"; exit 1; }
  for n in $(cat "$REPO/git-hooks/NAMES") lib.sh; do
    o=$(origen_githook "$n"); d="$GITHOOKS_DIR/$n"
    if es_nuestro "$d" "$o"; then manifiesto_add "link$TAB$d$TAB$o"; continue; fi
    if hacer "enlazar $d -> $o"; then
      ln -s "$o" "$d" || { error "no se pudo enlazar $d"; exit 1; }
      manifiesto_add "link$TAB$d$TAB$o"
    fi
  done
  actual=$(git config --global --get core.hooksPath 2>/dev/null)
  case $actual in "~/"*) actual="$HOME/${actual#"~/"}" ;; esac
  if [ -z "$actual" ]; then
    if hacer "git config --global core.hooksPath $GITHOOKS_DIR"; then
      # Se anota antes de cambiarlo: si se corta entre ambos, uninstall lo deshace igual
      # (quitar una clave que no existe no hace dano).
      manifiesto_add "gitconfig${TAB}core.hooksPath$TAB$GITHOOKS_DIR"
      git config --global core.hooksPath "$GITHOOKS_DIR" || { error "no se pudo fijar core.hooksPath"; exit 1; }
    fi
  elif [ "$actual" != "$GITHOOKS_DIR" ]; then
    aviso "core.hooksPath ya vale '$actual'; no se cambia (los hooks de $GITHOOKS_DIR no se usaran)"
  fi
fi
paso githooks

# --- settings.json (archivo generado, nunca enlace) ------------------------
node "$REPO/lib/merge-settings.mjs" --dir "$REPO" --os "$OS" --machine "$MENV" \
  --home "$HOME" --out "$SET_TMP" || { error "no se pudo generar settings.json"; exit 1; }
SET="$CLAUDE_DIR/settings.json"
SET_PREEX=0
if [ -f "$SET" ] && [ ! -L "$SET" ] && cmp -s "$SET_TMP" "$SET"; then
  info "settings.json al dia"
  SET_PREEX=1
else
  if [ -e "$SET" ] || [ -L "$SET" ]; then
    if hacer "respaldar settings.json actual como settings.json.p4-bak-$TS"; then
      respaldo_dir || { error "no se pudo crear el respaldo"; exit 1; }
      if [ -L "$SET" ]; then mv "$SET" "$RESPALDO/settings.json.p4-bak-$TS"
      else cp -p "$SET" "$RESPALDO/settings.json.p4-bak-$TS"
      fi || { error "no se pudo respaldar settings.json"; exit 1; }
    fi
  fi
  asegurar_dir "$CLAUDE_DIR" || { error "no se pudo crear $CLAUDE_DIR"; exit 1; }
  if hacer "generar $SET"; then
    # Se anota antes de escribir: si se corta, repetir no lo toma por preexistente.
    manifiesto_add "settings$TAB$SET${TAB}generado"
    cp "$SET_TMP" "$CLAUDE_DIR/.settings.json.p4-nuevo" \
      && mv -f "$CLAUDE_DIR/.settings.json.p4-nuevo" "$SET" || { error "no se pudo escribir $SET"; exit 1; }
  fi
fi
# Ya identico al generado y sin linea previa en el manifiesto: lo tenia la usuaria
# (o una instalacion anterior sin manifiesto); uninstall no lo borra.
if [ "$SET_PREEX" = 1 ] && ! { [ -f "$CLAUDE_DIR/.p4-manifest" ] && grep -q "^settings$TAB" "$CLAUDE_DIR/.p4-manifest"; }; then
  manifiesto_add "settings$TAB$SET${TAB}preexistente"
fi
paso settings

# --- MCP -------------------------------------------------------------------
if [ "$DRY" = 1 ]; then
  info "simulacion: registrar los MCP de mcp.json segun machine.env ($OS)"
else
  MCP_REGISTER_DIR="$REPO/lib"
  export MCP_REGISTER_DIR
  . "$REPO/lib/mcp-register.sh"
  mcp_register "$REPO/mcp.json" "$MENV" "$OS" || { error "fallo el registro de MCP"; exit 1; }
fi
paso mcp

if [ -n "$RESPALDO" ]; then info "listo; respaldo en $RESPALDO"; else info "listo"; fi
exit 0
