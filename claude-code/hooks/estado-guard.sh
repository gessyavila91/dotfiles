#!/bin/sh
# Hook PreToolUse de Claude Code (P5b §4.2b): deniega `git commit` si hay un plan
# `en ejecución` y el commit no lo incluye. Guarda de disciplina, no de seguridad:
# sin jq o ante cualquier duda, no decide nada.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

LIB=${EST_LIB:-"$(dirname "$0")/estado-lib.sh"}
# shellcheck disable=SC1090
. "$LIB" || exit 0

[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CMD" ] || exit 0
[ -n "$DIR" ] || DIR=$(pwd)

# Salida rápida: sin "commit" en el texto no hay nada que vigilar.
case $CMD in *commit*) ;; *) exit 0 ;; esac
# Marca de exención en cualquier parte del comando (-m, heredoc, ...).
case $CMD in *'[sin-plan]'*) exit 0 ;; esac

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Parte el comando en segmentos (&&, ||, ;, |, &, saltos de línea, paréntesis, comillas
# invertidas) respetando comillas. Un segmento por línea, tokens separados por US,
# ya sin comillas.
US=$(printf '\037')
split_segments() {
  CMD_IN=$1 awk '
  function endtok() { if (have || tok != "") { line = line (nt > 0 ? US : "") tok; nt++ } tok = ""; have = 0 }
  function endseg() { endtok(); if (nt > 0) print line; line = ""; nt = 0 }
  # Primer token del segmento en curso, sin ruta ni asignaciones previas.
  function cmdname(   l, a, k, w) {
    l = line (nt > 0 ? US : "") tok; k = split(l, a, US)
    for (w = 1; w <= k; w++) {
      if (a[w] ~ /=/ || a[w] == "sudo" || a[w] == "env" || a[w] == "command" || a[w] == "time" || a[w] == "exec" || a[w] == "nohup") continue
      sub(/.*\//, "", a[w]); return a[w]
    }
    return ""
  }
  BEGIN {
    US = "\037"; SQ = "\047"; DQ = "\""
    s = ENVIRON["CMD_IN"]; n = length(s); q = ""; tok = ""; have = 0; line = ""; nt = 0; nh = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q == SQ) { if (c == SQ) q = ""; else tok = tok c; continue }
      if (q == DQ) {
        if (c == "\\" && i < n) { i++; tok = tok substr(s, i, 1) }
        else if (c == DQ) q = ""
        else tok = tok (c == "\n" ? " " : c)
        continue
      }
      if (c == "\\" && i < n) { i++; tok = tok substr(s, i, 1); have = 1 }
      else if (c == SQ) { q = SQ; have = 1 }
      else if (c == DQ) { q = DQ; have = 1 }
      else if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<" && substr(s, i - 1, 1) != "<") {
        # Heredoc (<<WORD, <<-WORD, con comillas simples o dobles; no <<<). El cuerpo se omite salvo en sh/bash/zsh/git.
        j = i + 2; strip = 0
        if (substr(s, j, 1) == "-") { strip = 1; j++ }
        while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
        d = ""; dq = ""
        while (j <= n) {
          e = substr(s, j, 1)
          if (dq != "") { if (e == dq) dq = ""; else d = d e }
          else if (e == SQ || e == DQ) dq = e
          else if (e == " " || e == "\t" || e == "\n" || e == ";" || e == "|" || e == "&" || e == "(" || e == ")" || e == "<" || e == ">") break
          else d = d e
          j++
        }
        cn = cmdname()
        if (d != "" && cn != "sh" && cn != "bash" && cn != "zsh" && cn != "git") { nh++; hd[nh] = d; hs[nh] = strip }
        endtok(); i = j - 1
      }
      else if (c == " " || c == "\t") endtok()
      else if (c == "\n") {
        endseg()
        # Salta los cuerpos de heredoc pendientes hasta su delimitador.
        for (h = 1; h <= nh; h++) {
          i++
          while (i <= n) {
            k = index(substr(s, i), "\n"); if (k == 0) { ln = substr(s, i); i = n + 1 } else { ln = substr(s, i, k - 1); i += k }
            if (hs[h]) sub(/^\t+/, "", ln)
            if (ln == hd[h]) break
          }
          i--
        }
        nh = 0
      }
      else if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`" || c == "\n") endseg()
      else tok = tok c
    }
    endseg()
  }'
}

# cluster_has <letra> <letras-con-valor> <arg>: la agrupación corta (-abc) contiene la letra
# antes de llegar a una opción que consume el resto como valor.
cluster_has() {
  _cs=${3#-}
  while [ -n "$_cs" ]; do
    _cc=${_cs%"${_cs#?}"}; _cs=${_cs#?}
    [ "$_cc" = "$1" ] && return 0
    case $2 in *"$_cc"*) return 1 ;; esac
  done
  return 1
}

set_dir() {
  case $1 in
    /*) GDIR=$1 ;;
    *) GDIR=$GDIR/$1 ;;
  esac
}

ADDED=""   # planes (raíz/ruta relativa, uno por línea) añadidos con `git add` antes del commit

# check_git <args...>: solo `add` y `commit`.
check_git() {
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      -C) shift; [ $# -gt 0 ] && set_dir "$1" ;;
      -c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env) shift ;;
      -*) ;;
      *) break ;;
    esac
    shift
  done
  [ $# -gt 0 ] || return 0
  SUB=$1; shift
  case $SUB in add|commit) ;; *) return 0 ;; esac

  ROOT=$(git -C "$GDIR" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ "$(git -C "$ROOT" config --bool gitflow-guard.exempt 2>/dev/null)" = true ] && return 0
  set +f; PLANS=$(est_active_plans "$ROOT"); set -f
  [ -n "$PLANS" ] || return 0

  if [ "$SUB" = add ]; then
    _gp=$(cd "$GDIR" 2>/dev/null && pwd -P) || _gp=$GDIR
    for _a in "$@"; do
      case $_a in
        .|-A|--all) _all=1 ;;
        -*) continue ;;
        /*) _all=0; _full=$_a ;;
        *) _all=0; _full=$_gp/$_a ;;
      esac
      for _p in $PLANS; do
        _rel=${_p#"$ROOT"/}
        if [ "${_all:-0}" -eq 1 ] || [ "$_full" = "$_p" ] || [ "$_full" = "$ROOT/$_rel" ]; then
          [ -n "$(git -C "$ROOT" status --porcelain -- "$_rel" 2>/dev/null)" ] || continue
          ADDED="$ADDED
$ROOT/$_rel
"
        fi
      done
      _all=0
    done
    return 0
  fi

  # commit: -a / -F
  _auto=0; _skip=0; _msgf=""
  for _a in "$@"; do
    if [ "$_skip" -eq 1 ]; then _skip=0; _msgf=$_a; continue; fi
    if [ "$_skip" -eq 2 ]; then _skip=0; continue; fi
    case $_a in
      --all) _auto=1 ;;
      -F|--file) _skip=1 ;;
      --file=*) _msgf=${_a#--file=} ;;
      -m|-C|-c|-t|--message|--author|--date) _skip=2 ;;
      --*) ;;
      -[A-Za-z]*) cluster_has a mFCcStu "$_a" && _auto=1
                  case $_a in *F) _skip=1 ;; esac ;;
    esac
  done
  if [ -n "$_msgf" ]; then
    case $_msgf in /*) ;; *) _msgf=$GDIR/$_msgf ;; esac
    [ -f "$_msgf" ] && grep -F '[sin-plan]' "$_msgf" >/dev/null 2>&1 && return 0
  fi

  _staged=$(git -C "$ROOT" diff --cached --name-only 2>/dev/null)
  _dirty=""
  [ "$_auto" -eq 1 ] && _dirty=$(git -C "$ROOT" diff --name-only 2>/dev/null)
  _first=""
  for _p in $PLANS; do
    _rel=${_p#"$ROOT"/}
    [ -n "$_first" ] || _first=$_rel
    _hit="
$_staged
$_dirty
"
    case $ADDED in *"
$ROOT/$_rel
"*) return 0 ;; esac
    case $_hit in *"
$_rel
"*) return 0 ;; esac
  done
  _list=$(printf '%s' "$PLANS" | sed "s|$ROOT/||" | tr '\n' ' ')
  deny "A plan is in execution (${_list% }). Mark the finished step [x] in it and stage it in this commit; if it is finished, set its status line to \`ejecutado\`; if this commit completes no plan step (unrelated work, or a fix to an already-ticked step), add [sin-plan] to the message."
}

GDIR=$DIR
SEGS=$(split_segments "$CMD")
set -f
OLDIFS=$IFS
while IFS= read -r seg; do
  IFS=$US
  # shellcheck disable=SC2086
  set -- $seg
  IFS=$OLDIFS
  while [ $# -gt 0 ]; do
    case $1 in
      *=*|sudo|env|command|time|exec|nohup) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  case $1 in
    cd) [ $# -ge 2 ] && set_dir "$2" ;;
    git) SEG_DIR=$GDIR; check_git "$@"; GDIR=$SEG_DIR ;;
  esac
done <<EOT
$SEGS
EOT
exit 0
