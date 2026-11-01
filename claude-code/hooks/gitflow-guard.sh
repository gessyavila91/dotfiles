#!/bin/sh
# Hook PreToolUse de Claude Code: aplica Gitflow a Claude (spec P2 §4.2).
# Análisis por patrones y de mejor esfuerzo; la red de seguridad es el pre-push de git.
# Deniega imprimiendo JSON `deny` y saliendo con 0; sin decisión no imprime nada.

INPUT=$(cat)

# Sin jq: falla cerrado solo para lo peligroso.
if ! command -v jq >/dev/null 2>&1; then
  case $INPUT in
    *"git push"*|*"gh pr merge"*)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"gitflow-guard: jq is not installed, so this git push / gh pr merge cannot be checked. Install jq or ask the user to run it."}}'
      ;;
  esac
  exit 0
fi

LIB=${GFG_LIB:-"$(dirname "$0")/gitflow-guard-lib.sh"}
# shellcheck disable=SC1090
. "$LIB" || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CMD" ] || exit 0
[ -n "$DIR" ] || DIR=$(pwd)

deny() {
  jq -n --arg r "gitflow-guard: $1" \
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

# set_dir <ruta>: actualiza GDIR relativo al directorio efectivo actual.
set_dir() {
  case $1 in
    /*) GDIR=$1 ;;
    *) GDIR=$GDIR/$1 ;;
  esac
}

# deny3: la regla 3 no aplica a repos exentos.
deny3() { [ "$EXEMPT" -eq 1 ] || deny "$1"; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

branch_of() { git -C "$GDIR" symbolic-ref --short -q HEAD 2>/dev/null; }

# dest_of <refspec> <rama actual>: rama destino de un refspec (sin + inicial).
dest_of() {
  _r=${1#+}
  case $_r in *:*) _r=${_r#*:} ;; esac
  _r=${_r#refs/heads/}
  [ "$_r" = "HEAD" ] && _r=$2
  printf '%s' "$_r"
}

check_push() {
  _cur=$(branch_of)
  _lease=0; _refs=0; _skip=0; _pos=0; _tags=0; _all=0
  for _a in "$@"; do
    if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
    case $_a in
      *\>|*\<) _skip=1 ;;   # redirección con destino en el token siguiente
      *\>*|\<*) ;;          # redirección pegada (2>, >f): no es refspec
      --no-verify) deny "Rule 2: --no-verify skips the git hooks. Do not bypass them; ask the user." ;;
      --force-with-lease|--force-with-lease=*) _lease=1 ;;
      --force|--force-if-includes) [ "$_a" = "--force" ] && deny3 "Rule 3: force push is blocked. Ask the user; use --force-with-lease only on your own non-protected branch." ;;
      --tags) _tags=1 ;;
      --all|--mirror) _all=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) _skip=1 ;;
      --*) ;;
      -[A-Za-z]*) cluster_has f o "$_a" && deny3 "Rule 3: force push (-f) is blocked. Ask the user; use --force-with-lease only on your own non-protected branch." ;;
      -*) ;;
      *)
        _pos=$((_pos + 1))
        [ "$_pos" -eq 1 ] && continue   # remoto
        _refs=$((_refs + 1))
        case $_a in +*) deny3 "Rule 3: a '+' refspec forces the push. Ask the user; use --force-with-lease only on your own non-protected branch." ;; esac
        _d=$(dest_of "$_a" "$_cur")
        if [ -n "$_d" ] && gfg_is_protected "$GDIR" "$_d"; then
          [ "$_lease" -eq 1 ] && deny3 "Rule 3: --force-with-lease toward protected branch '$_d' is blocked. Open a PR instead."
          [ "$EXEMPT" -eq 1 ] || deny "Rule 1: pushing to protected branch '$_d' is blocked. Push a feature branch and open a PR."
        fi
        ;;
    esac
  done
  [ "$EXEMPT" -eq 1 ] && return 0
  if [ "$_all" -eq 1 ]; then
    deny "Rule 1: --all/--mirror would push protected branches. Push a feature branch and open a PR."
  fi
  if [ "$_refs" -eq 0 ] && [ "$_tags" -eq 0 ] && [ -n "$_cur" ] && gfg_is_protected "$GDIR" "$_cur"; then
    if [ "$_lease" -eq 1 ]; then
      deny "Rule 3: --force-with-lease from protected branch '$_cur' is blocked. Open a PR instead."
    fi
    deny "Rule 1: pushing from protected branch '$_cur' is blocked. Create a feature branch and open a PR."
  fi
  return 0
}

check_commit_flags() {  # $1 = subcomando; resto = args
  _sub=$1; shift
  _skip=0
  for _a in "$@"; do
    if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
    case $_a in
      --no-verify) deny "Rule 2: --no-verify skips the git hooks. Do not bypass them; ask the user." ;;
      -m|-F|-C|-c|-t|--message|--file|--author|--date) _skip=1 ;;
      --*) ;;
      -[A-Za-z]*)
        if [ "$_sub" = "commit" ] && cluster_has n mFCcStu "$_a"; then
          deny "Rule 2: -n (--no-verify) skips the git hooks. Do not bypass them; ask the user."
        fi ;;
    esac
  done
}

check_git() {
  shift  # git
  while [ $# -gt 0 ]; do
    case $1 in
      -C) shift; [ $# -gt 0 ] && set_dir "$1" ;;
      -c)
        shift
        case $(lower "${1:-}") in core.hookspath*) deny "Rule 6: overriding core.hooksPath disables the Gitflow git hooks. Ask the user." ;; esac ;;
      --config-env=*)
        case $(lower "${1#--config-env=}") in core.hookspath*) deny "Rule 6: overriding core.hooksPath disables the Gitflow git hooks. Ask the user." ;; esac ;;
      --config-env)
        shift
        case $(lower "${1:-}") in core.hookspath*) deny "Rule 6: overriding core.hooksPath disables the Gitflow git hooks. Ask the user." ;; esac ;;
      --git-dir|--work-tree|--namespace|--exec-path|--super-prefix) shift ;;
      -*) ;;
      *) break ;;
    esac
    shift
  done
  [ $# -gt 0 ] || return 0
  SUB=$1; shift
  EXEMPT=0
  gfg_is_exempt "$GDIR" && EXEMPT=1

  case $SUB in
    config)
      # Solo se vigila lo que menciona core.hooksPath; las lecturas se permiten.
      _hp=0; _mut=0; _rd=0; _pos=0; _skip=0; _first=1
      for _a in "$@"; do
        if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
        case $(lower "$_a") in *core.hookspath*) _hp=1 ;; esac
        case $_a in
          --unset|--unset-all|--replace-all|--add|-e|--edit|--rename-section|--remove-section) _mut=1 ;;
          --get|--get-all|--get-regexp|--get-urlmatch|--list|-l|--show-origin|--show-scope) _rd=1 ;;
          -f|--file|--blob|--type|-t|--default|--comment) _skip=1 ;;
          -*) ;;
          *)
            if [ "$_first" -eq 1 ]; then
              case $_a in
                set|unset) _mut=1 ;;
                get|list) _rd=1 ;;
                *) _pos=$((_pos + 1)) ;;
              esac
            else
              _pos=$((_pos + 1))
            fi
            _first=0 ;;
        esac
      done
      if [ "$_hp" -eq 1 ]; then
        # Escritura: opción mutante, subcomando set/unset o clave + valor.
        if [ "$_mut" -eq 1 ] || { [ "$_rd" -eq 0 ] && [ "$_pos" -ge 2 ]; }; then
          deny "Rule 6: changing core.hooksPath disables the Gitflow git hooks. Ask the user."
        fi
      fi ;;
    commit|merge) check_commit_flags "$SUB" "$@" ;;
    push) check_push "$@" ;;
  esac

  case $SUB in
    commit|merge|rebase|cherry-pick)
      [ "$EXEMPT" -eq 1 ] && return 0
      for _a in "$@"; do
        case $_a in --abort|--quit|--continue|--skip) return 0 ;; esac
      done
      _cur=$(branch_of)
      if [ -n "$_cur" ] && gfg_is_protected "$GDIR" "$_cur"; then
        deny "Rule 4: git $SUB on protected branch '$_cur' is blocked. Create a feature branch first and open a PR."
      fi ;;
  esac
}

check_gh() {
  shift  # gh
  case ${1:-} in
    pr)
      case ${2:-} in
        merge) deny "Rule 5: Claude never merges PRs; the user does, on GitHub. Ask the user." ;;
        review)
          for _a in "$@"; do
            case $_a in --approve|-a) deny "Rule 5: Claude never approves PRs; the user does, on GitHub. Ask the user." ;; esac
          done ;;
      esac ;;
    api)
      shift
      for _a in "$@"; do
        case $(lower "$_a") in
          *approve*) deny "Rule 5: gh api calls that approve a PR are blocked; the user approves on GitHub. Ask the user." ;;
          *mergepullrequest*) deny "Rule 5: gh api calls to a merge endpoint are blocked; the user merges PRs on GitHub. Ask the user." ;;
        esac
        case $_a in
          -*) ;;
          *\?*) case ${_a%%\?*} in */merge|*/merge/*|*/merges) deny "Rule 5: gh api calls to a merge endpoint are blocked; the user merges PRs on GitHub. Ask the user." ;; esac ;;
          */merge|*/merge/*|*/merges) deny "Rule 5: gh api calls to a merge endpoint are blocked; the user merges PRs on GitHub. Ask the user." ;;
        esac
      done ;;
  esac
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
  # Prefijos que no cambian el comando: VAR=x, sudo, env, command, time, exec, nohup.
  while [ $# -gt 0 ]; do
    case $1 in
      *=*)
        case $(lower "$1") in
          git_config_key_*=*core.hookspath*|git_config_parameters=*core.hookspath*)
            deny "Rule 6: overriding core.hooksPath via the environment disables the Gitflow git hooks. Ask the user." ;;
        esac
        shift ;;
      sudo|env|command|time|exec|nohup) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  case $1 in
    cd) [ $# -ge 2 ] && set_dir "$2" ;;
    git) SEG_DIR=$GDIR; check_git "$@"; GDIR=$SEG_DIR ;;
    gh) check_gh "$@" ;;
  esac
done <<EOT
$SEGS
EOT
exit 0
