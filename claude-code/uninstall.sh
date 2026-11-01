#!/bin/sh
# uninstall.sh: deshace lo que install.sh creo en $HOME. POSIX sh.
# Uso: uninstall.sh [--dry-run]
#
# Lee el manifiesto $HOME/.claude/.p4-manifest (formato en lib/common.sh) y quita solo lo
# que anota: enlaces que siguen apuntando a este clon, core.hooksPath si lo fijo el
# instalador y conserva su valor, y carpetas que creo y quedan vacias. settings.json se
# restaura desde la copia del respaldo (la mas reciente que la tenga); sin copia, se borra
# solo si es identica a la que generaria el instalador (si no, se deja y se avisa). Lo
# movido al respaldo se copia de vuelta (de todos los respaldos del manifiesto, del mas
# antiguo al mas reciente); el respaldo nunca se borra. Lo adoptado al repo no se borra del
# repo. Lo desconocido en ~/.claude se deja. El manifiesto se quita al final.
#
# Antes de cambiar nada comprueba todo; si el estado es incoherente (linea desconocida,
# enlace de otro clon, ruta fuera de HOME, respaldo ausente, destino de restauracion
# ocupado por otra cosa) sale con 2 sin tocar nada.
# Codigos: 0 bien; 1 nada instalado (no hay manifiesto); 2 estado incoherente.
# No anula el registro de los MCP (viven en ~/.claude.json, que no se edita a mano):
# al terminar imprime los `claude mcp remove` que debe ejecutar la usuaria.

case ${HOME:-} in
  /*) [ -d "$HOME" ] || { echo "error: HOME no es una carpeta: $HOME" >&2; exit 1; } ;;
  *) echo "error: HOME debe ser una ruta absoluta (vale '${HOME:-}')" >&2; exit 1 ;;
esac
SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
REPO=$SELF_DIR
. "$REPO/lib/common.sh"

DRY=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) error "opcion desconocida: $a"; echo "uso: uninstall.sh [--dry-run]" >&2; exit 1 ;;
  esac
done

CLAUDE_DIR="$HOME/.claude"
MANIFEST="$CLAUDE_DIR/.p4-manifest"
TS=$(date +%Y%m%d-%H%M%S)
NL='
'
detectar_os || OS=linux
[ "$DRY" = 1 ] && info "modo simulacion: no se escribe nada"

if [ ! -f "$MANIFEST" ]; then
  info "nada instalado: no existe $MANIFEST"
  exit 1
fi

INCOH=0
incoherente() { error "estado incoherente: $*"; INCOH=1; }
bajo_home() { case $1 in "$HOME"/*) return 0 ;; *) return 1 ;; esac; }

# --- lectura y validacion del manifiesto -------------------------------------
BACKUPS=; DIRS=; SETTINGS=; SET_EXTRA=; GITCFG_VAL=; HAY_GITCFG=0
while IFS="$TAB" read -r kind ruta extra; do
  [ -n "$kind$ruta" ] || continue
  case $kind in
    backup=*)
      b=${kind#backup=}
      [ -d "$b" ] || incoherente "falta la carpeta de respaldo $b"
      bajo_home "$b" || incoherente "respaldo fuera de HOME: $b"
      BACKUPS="$BACKUPS$b$NL" ;;
    dir)
      bajo_home "$ruta" || incoherente "carpeta fuera de HOME: $ruta"
      DIRS="$ruta$NL$DIRS" ;;  # la mas interna primero
    link)
      bajo_home "$ruta" || incoherente "enlace fuera de HOME: $ruta"
      case $extra in "$REPO"/*) ;; *) incoherente "$ruta apunta a $extra, que no es de este clon ($REPO)" ;; esac ;;
    settings) bajo_home "$ruta" || incoherente "settings fuera de HOME: $ruta"; SETTINGS=$ruta; SET_EXTRA=$extra ;;
    gitconfig) HAY_GITCFG=1; GITCFG_VAL=$extra ;;
    adopt) ;;
    *) incoherente "linea desconocida en el manifiesto: $kind" ;;
  esac
done < "$MANIFEST"

# --- restauracion desde el respaldo ------------------------------------------
# restaurar_todo <comprobar|hacer>: recorre, con una cola (sh no tiene variables locales),
# cada entrada de cada respaldo, del mas antiguo al mas reciente, y la lleva a su sitio
# en HOME. Si origen y destino son carpetas, entra. Un destino que ya es igual
# (restauracion previa interrumpida) o un enlace nuestro (se quita antes) vale; otro
# destino ocupado es incoherencia. En la raiz del respaldo, settings.json.p4-* no son
# rutas de HOME y se saltan.
restaurar_todo() {
  COLA=; VISTOS=
  while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    for _x in "$_b"/* "$_b"/.[!.]*; do
      [ -e "$_x" ] || [ -L "$_x" ] || continue
      case ${_x##*/} in settings.json.p4-*) continue ;; esac
      COLA="$COLA$_x$TAB$HOME/${_x#"$_b"/}$NL"
    done
  done <<EOF
$BACKUPS
EOF
  while [ -n "$COLA" ]; do
    _l=${COLA%%"$NL"*}; COLA=${COLA#"$_l$NL"}
    _o=${_l%%"$TAB"*}; _d=${_l#*"$TAB"}
    if [ -d "$_o" ] && [ ! -L "$_o" ] && [ -d "$_d" ] && [ ! -L "$_d" ]; then
      for _e in "$_o"/* "$_o"/.[!.]*; do
        [ -e "$_e" ] || [ -L "$_e" ] || continue
        COLA="$COLA$_e$TAB$_d/${_e##*/}$NL"
      done
      continue
    fi
    if [ "$1" = comprobar ]; then
      # Dos respaldos con la misma ruta (o una dentro de la otra) y contenido distinto:
      # no se adivina cual vale.
      while IFS="$TAB" read -r _vo _vd; do
        [ -n "$_vd" ] || continue
        if [ "$_vd" = "$_d" ]; then
          if { [ -L "$_vo" ] && [ -L "$_o" ] && [ "$(readlink "$_vo")" = "$(readlink "$_o")" ]; } \
             || { [ ! -L "$_vo" ] && [ ! -L "$_o" ] && mismo_contenido "$_vo" "$_o"; }; then :
          else incoherente "$_d esta en dos respaldos con contenido distinto ($_vo y $_o)"
          fi
        else
          case $_vd/ in "$_d"/*) incoherente "$_d y $_vd estan en respaldos distintos y se pisarian" ;; esac
          case $_d/ in "$_vd"/*) incoherente "$_d y $_vd estan en respaldos distintos y se pisarian" ;; esac
        fi
      done <<EOF
$VISTOS
EOF
      VISTOS="$VISTOS$_o$TAB$_d$NL"
    fi
    if [ -e "$_d" ] || [ -L "$_d" ]; then
      if enlace_al_repo "$_d" "$REPO"; then
        :  # nuestro: la fase de enlaces lo quita antes de restaurar
      elif [ -L "$_o" ] && [ -L "$_d" ] && [ "$(readlink "$_o")" = "$(readlink "$_d")" ]; then
        continue
      elif [ ! -L "$_o" ] && [ ! -L "$_d" ] && mismo_contenido "$_o" "$_d"; then
        continue
      else
        incoherente "no se puede restaurar $_d: ya existe y es distinto de la copia del respaldo"
        continue
      fi
    fi
    [ "$1" = hacer ] || continue
    if [ "$DRY" != 1 ] && { [ -e "$_d" ] || [ -L "$_d" ]; }; then continue; fi
    hacer "restaurar $_d desde el respaldo" || continue
    mkdir -p "$(dirname "$_d")" && cp -RPp "$_o" "$_d" || { error "no se pudo restaurar $_d"; exit 1; }
  done
}

# --- settings.json: de que copia se restaura, o si se puede borrar -----------
SET_BAK=; SET_ACCION=nada; SET_TMP=$(mktemp) || exit 1
AVISOS=
trap 'rm -f "$SET_TMP"' EXIT
aviso_final() { aviso "$*"; AVISOS="$AVISOS$*$NL"; }
if [ -n "$SETTINGS" ]; then
  while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    for _x in "$_b"/settings.json.p4-bak-*; do
      if [ -e "$_x" ] || [ -L "$_x" ]; then SET_BAK=$_x; fi
    done
  done <<EOF
$BACKUPS
EOF
  if [ ! -e "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
    SET_ACCION=ausente
  elif [ -L "$SETTINGS" ]; then
    SET_ACCION=dejar
  elif [ -n "$SET_BAK" ]; then
    SET_ACCION=restaurar
  elif [ "$SET_EXTRA" = preexistente ]; then
    SET_ACCION=conservar
  elif settings_regenerar "$REPO" "$OS" "$SET_TMP" 2>/dev/null && cmp -s "$SET_TMP" "$SETTINGS"; then
    SET_ACCION=borrar
  else
    SET_ACCION=dejar
  fi
fi

restaurar_todo comprobar
if [ "$INCOH" = 1 ]; then
  error "no se toca nada; revise el manifiesto $MANIFEST o repare el estado a mano"
  exit 2
fi

# --- 1. enlaces --------------------------------------------------------------
while IFS="$TAB" read -r kind ruta extra; do
  [ "$kind" = link ] || continue
  if enlace_al_repo "$ruta" "$REPO"; then
    if hacer "quitar enlace $ruta"; then
      rm -f "$ruta" || { error "no se pudo quitar $ruta"; exit 1; }
    fi
  elif [ -e "$ruta" ] || [ -L "$ruta" ]; then
    aviso "$ruta ya no es un enlace a este clon; no se toca"
  fi
done < "$MANIFEST"

# --- 2. settings.json --------------------------------------------------------
case $SET_ACCION in
  restaurar)
    # Si el actual tiene cambios a mano, se guarda junto al respaldo antes de pisarlo.
    if ! { settings_regenerar "$REPO" "$OS" "$SET_TMP" 2>/dev/null && cmp -s "$SET_TMP" "$SETTINGS"; }; then
      _prev=$(dirname "$SET_BAK")/settings.json.p4-previo-$TS
      if hacer "guardar el settings.json actual en $_prev"; then
        cp -p "$SETTINGS" "$_prev" || { error "no se pudo guardar $SETTINGS"; exit 1; }
        aviso_final "$SETTINGS tenia cambios posteriores a la instalacion; se guardo como $_prev"
      fi
    fi
    if hacer "restaurar $SETTINGS desde $SET_BAK"; then
      rm -f "$SETTINGS.p4-tmp"
      cp -RPp "$SET_BAK" "$SETTINGS.p4-tmp" && mv -f "$SETTINGS.p4-tmp" "$SETTINGS" \
        || { error "no se pudo restaurar $SETTINGS"; exit 1; }
    fi ;;
  borrar)
    if hacer "quitar $SETTINGS (identico al generado)"; then rm -f "$SETTINGS"; fi ;;
  conservar) info "$SETTINGS ya existia antes de instalar (identico al generado); se conserva" ;;
  ausente)
    if [ -n "$SET_BAK" ]; then
      aviso_final "$SETTINGS no existe pero hay una copia en $SET_BAK; no se restaura en silencio. Para recuperarla: cp -p '$SET_BAK' '$SETTINGS'"
    fi ;;
  dejar) aviso_final "$SETTINGS difiere del generado y no hay copia en el respaldo (o no es un archivo normal); se deja como esta" ;;
esac

# --- 3. originales movidos al respaldo ---------------------------------------
restaurar_todo hacer
if [ "$INCOH" = 1 ]; then
  error "la restauracion encontro un conflicto; se conserva el manifiesto $MANIFEST. Revise y repita"
  exit 2
fi

# --- 4. core.hooksPath --------------------------------------------------------
if [ "$HAY_GITCFG" = 1 ]; then
  actual=$(git config --global --get core.hooksPath 2>/dev/null)
  if [ "$actual" = "$GITCFG_VAL" ]; then
    if hacer "git config --global --unset core.hooksPath"; then
      git config --global --unset core.hooksPath || { error "no se pudo quitar core.hooksPath"; exit 1; }
    fi
  else
    info "core.hooksPath ya no vale '$GITCFG_VAL' (vale '$actual'); no se toca"
  fi
fi

# --- 5. carpetas creadas, manifiesto -----------------------------------------
# ~/.claude va al final: contiene el manifiesto.
quitar_dirs() {
  while IFS= read -r _dd; do
    { [ -n "$_dd" ] && [ -d "$_dd" ] && [ ! -L "$_dd" ]; } || continue
    if [ "$_dd" = "$CLAUDE_DIR" ] && [ "$1" != fin ]; then continue; fi
    if [ "$DRY" = 1 ]; then info "simulacion: quitar carpeta $_dd si queda vacia"
    elif rmdir "$_dd" 2>/dev/null; then info "carpeta vacia quitada: $_dd"
    fi
  done <<EOF
$DIRS
EOF
}
quitar_dirs previo
if hacer "quitar el manifiesto $MANIFEST"; then
  rm -f "$MANIFEST" || { error "no se pudo quitar el manifiesto"; exit 1; }
fi
quitar_dirs fin

# --- MCP: no se anulan aqui ---------------------------------------------------
info "los MCP siguen registrados (viven en ~/.claude.json, que no se edita a mano). Para quitarlos:"
node -e '
  for (const e of JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")))
    console.log("  claude mcp remove --scope user " + e.name);' "$REPO/mcp.json" 2>/dev/null
if [ -n "$AVISOS" ]; then
  info "resumen de avisos:"
  printf '%s' "$AVISOS" | sed 's/^/  - /'
fi
[ "$DRY" = 1 ] || info "desinstalado; los respaldos en ~/Respaldos no se borran"
exit 0
