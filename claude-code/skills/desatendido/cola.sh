#!/bin/sh
# desatendido — sessionTestClaude P5c
# cola.sh [-C repo] <subcomando>: cola persistente de planes, rama base y entrega.
#   crear <plan>… | actual | siguiente | cerrar <plan> | rama <plan> | rama-existe <plan> | rama-base <plan> | pr-base
#   entrega <plan> parcial|final [motivo]
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -n "$EST_LIB" ] && [ -f "$EST_LIB" ]; then
  . "$EST_LIB"
elif [ -f "$HOME/.claude/skills/estado/estado-lib.sh" ]; then
  . "$HOME/.claude/skills/estado/estado-lib.sh"
elif [ -f "$SELF_DIR/../estado/estado-lib.sh" ]; then
  . "$SELF_DIR/../estado/estado-lib.sh"
else
  echo "cola.sh: no encuentro estado-lib.sh" >&2; exit 2
fi

if [ "$1" = "-C" ]; then
  cd "$2" || exit 2
  shift 2
fi

ENTREGAS=docs/superpowers/entregas
cmd=$1
[ $# -gt 0 ] && shift

# nombre normalizado de un plan (sin fecha ni .md, minúsculas, guiones)
plan_name() {
  basename "$1" .md | sed 's/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-//' |
    tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# clave de orden de una cola: fecha + número de sufijo
queue_key() {
  qk_b=$(basename "$1" .md); qk_b=${qk_b#cola-}
  qk_d=$(printf '%s' "$qk_b" | cut -c1-10 | tr -d '-')
  case $qk_b in
    ??????????-*) qk_n=${qk_b#??????????-} ;;
    *) qk_n=1 ;;
  esac
  printf '%s%05d' "$qk_d" "$qk_n"
}

current_queue() {
  cq_best=""; cq_bk=""
  for cq_f in "$ENTREGAS"/cola-*.md; do
    [ -f "$cq_f" ] || continue
    grep -q '^- \[ \] ' "$cq_f" || continue
    cq_k=$(queue_key "$cq_f")
    if [ -z "$cq_bk" ] || [ "$cq_k" -gt "$cq_bk" ]; then cq_best=$cq_f; cq_bk=$cq_k; fi
  done
  [ -n "$cq_best" ] && printf '%s\n' "$cq_best"
  return 0
}

# mark_done <cola> <plan>
mark_done() {
  md_tmp="$1.tmp.$$"
  MD_P="$2" awk 'BEGIN { p = "- [ ] " ENVIRON["MD_P"] }
    $0 == p { print "- [x] " ENVIRON["MD_P"]; next } { print }' "$1" > "$md_tmp" && mv "$md_tmp" "$1"
}

default_branch() {
  db=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) && [ -n "$db" ] && { printf '%s\n' "${db#origin/}"; return; }
  db=$(git symbolic-ref --short HEAD 2>/dev/null) && [ -n "$db" ] && { printf '%s\n' "$db"; return; }
  for db in main master; do
    git show-ref --verify --quiet "refs/heads/$db" && { printf '%s\n' "$db"; return; }
  done
  git for-each-ref --format='%(refname:short)' --count=1 refs/heads 2>/dev/null
}

is_exempt() { [ "$(git config --bool gitflow-guard.exempt 2>/dev/null)" = true ]; }

# añade patrones al .git/info/exclude real (idempotente; vale en worktrees)
add_exclude() {
  ae_f=$(git rev-parse --git-path info/exclude 2>/dev/null) || return 0
  mkdir -p "$(dirname "$ae_f")"
  for ae_p in "$@"; do
    grep -qxF -- "$ae_p" "$ae_f" 2>/dev/null || printf '%s\n' "$ae_p" >> "$ae_f"
  done
}

pr_base() {
  if ! is_exempt &&
     { git show-ref --verify --quiet refs/heads/develop ||
       git show-ref --verify --quiet refs/remotes/origin/develop; }; then
    echo develop
  else
    default_branch
  fi
}

case $cmd in
  crear)
    [ $# -ge 1 ] || { echo "uso: cola.sh crear <plan>…" >&2; exit 2; }
    mkdir -p "$ENTREGAS"
    cr_d=$(date +%Y-%m-%d); cr_f="$ENTREGAS/cola-$cr_d.md"; cr_n=1
    while [ -e "$cr_f" ]; do cr_n=$((cr_n + 1)); cr_f="$ENTREGAS/cola-$cr_d-$cr_n.md"; done
    { printf '# Cola de ejecución desatendida %s\n\n' "$cr_d"
      for cr_p in "$@"; do printf -- '- [ ] %s\n' "$cr_p"; done; } > "$cr_f"
    add_exclude 'docs/superpowers/entregas/cola-*.md' '.superpowers/'
    printf '%s\n' "$cr_f"
    ;;
  actual)
    current_queue
    ;;
  siguiente)
    sg_q=$(current_queue)
    [ -n "$sg_q" ] || exit 0
    grep '^- \[ \] ' "$sg_q" | sed 's/^- \[ \] //' | while IFS= read -r sg_p; do
      if [ ! -f "$sg_p" ]; then
        echo "aviso: plan inexistente, se omite: $sg_p" >&2
        mark_done "$sg_q" "$sg_p"
      elif [ "$(est_plan_status "$sg_p")" = ejecutado ]; then
        mark_done "$sg_q" "$sg_p"
      else
        printf '%s\n' "$sg_p"; break
      fi
    done
    ;;
  cerrar)
    cl_q=$(current_queue)
    [ -n "$cl_q" ] || { echo "cola.sh: no hay cola abierta" >&2; exit 1; }
    mark_done "$cl_q" "$1"
    ;;
  rama)
    printf 'feature/%s\n' "$(plan_name "$1")"
    ;;
  rama-existe)
    re_b=$(plan_name "$1")
    git show-ref --verify --quiet "refs/heads/feature/$re_b" ||
      git show-ref --verify --quiet "refs/remotes/origin/feature/$re_b"
    exit $?
    ;;
  rama-base)
    rb_dep=$(sed -n 's/^> *Depende de: *//p' "$1" 2>/dev/null | head -n 1 | sed 's/[[:space:]]*$//')
    if [ -n "$rb_dep" ]; then
      rb_q=$(current_queue)
      if [ -n "$rb_q" ]; then
        rb_dn=$(basename "$rb_dep")
        rb_hit=$(sed -n 's/^- \[[ x]\] //p' "$rb_q" | RB_S="$1" RB_D="$rb_dn" awk '
          $0 == ENVIRON["RB_S"] { exit }
          { n = $0; sub(/.*\//, "", n); if (n == ENVIRON["RB_D"]) { print "si"; exit } }')
        [ -n "$rb_hit" ] && { printf 'feature/%s\n' "$(plan_name "$rb_dn")"; exit 0; }
      fi
    fi
    pr_base
    ;;
  pr-base)
    pr_base
    ;;
  entrega)
    [ $# -ge 2 ] || { echo "uso: cola.sh entrega <plan> parcial|final [motivo]" >&2; exit 2; }
    en_plan=$1; en_kind=$2; shift 2; en_why=$*
    case $en_kind in
      parcial) en_status="> Estado de la entrega: parcial — ${en_why:-sin motivo indicado}" ;;
      final) en_status="> Estado de la entrega: final" ;;
      *) echo "cola.sh: tipo de entrega inválido: $en_kind" >&2; exit 2 ;;
    esac
    mkdir -p "$ENTREGAS"
    en_n=$(plan_name "$en_plan"); en_f=""
    for en_c in "$ENTREGAS"/????-??-??-"$en_n".md; do
      [ -f "$en_c" ] && en_f=$en_c
    done
    [ -n "$en_f" ] || en_f="$ENTREGAS/$(date +%Y-%m-%d)-$en_n.md"
    if [ -f "$en_f" ]; then
      en_tmp="$en_f.tmp.$$"
      EN_S="$en_status" awk '/^> Estado de la entrega:/ { print ENVIRON["EN_S"]; next } { print }' "$en_f" > "$en_tmp" && mv "$en_tmp" "$en_f"
    else
      en_checks=$(awk '
        /^## Comprobaciones humanas[ \t]*$/ { f = 1; next }
        /^## / { f = 0 }
        f { print }' "$en_plan" 2>/dev/null | sed '/./,$!d')
      if [ -z "$en_checks" ]; then
        if ! is_exempt && git remote 2>/dev/null | grep -q .; then en_checks='- [ ] Revisar el PR'
        else en_checks="- [ ] Revisar los cambios en $(git symbolic-ref --short HEAD 2>/dev/null || echo la-rama-actual)"; fi
      fi
      {
        printf '# Entrega: %s\n\n%s\n\n' "$(plan_name "$en_plan")" "$en_status"
        printf '## Qué cambió\n\n'
        printf '## Comprobaciones humanas\n\n%s\n\n' "$en_checks"
        printf '## Decisiones que tomé\n\n'
        printf '## Pendientes menores\n\n'
        printf '## Cómo deshacer\n'
      } > "$en_f"
    fi
    printf '%s\n' "$en_f"
    ;;
  *)
    echo "uso: cola.sh [-C repo] crear|actual|siguiente|cerrar|rama|rama-existe|rama-base|pr-base|entrega" >&2
    exit 2
    ;;
esac
