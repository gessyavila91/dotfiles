#!/bin/sh
# estado — sessionTestClaude P5b
# estado.sh [--breve] [dir]: informe de continuidad del repo ("¿en qué estamos?").
EST_DIR=$(cd "$(dirname "$0")" && pwd)
. "$EST_DIR/estado-lib.sh"

est_brief=0
if [ "$1" = "--breve" ]; then est_brief=1; shift; fi
est_dir=${1:-.}

est_repo=$(git -C "$est_dir" rev-parse --show-toplevel 2>/dev/null) || {
  [ "$est_brief" -eq 1 ] || echo "No es un repo git."
  exit 0
}

# Recorte por bytes (LC_ALL=C) y luego se descartan los bytes UTF-8 incompletos del final.
EST_LEADP=$(printf '[\300-\377][\200-\277]*')
EST_LEAD="$EST_LEADP\$"
EST_MK=$(printf '\001')
est_short() { # <texto> <máx>: recorta con puntos suspensivos
  est_c=$(LC_ALL=C awk -v max="$2" '{ if (length($0) > max) print substr($0, 1, max - 4) "\001"; else print }' <<EOT
$1
EOT
)
  case $est_c in
    *"$(printf '\001')") est_c=${est_c%?}
      est_c=$(printf '%s' "$est_c" | LC_ALL=C sed "s/$EST_LEAD//")…
      ;;
  esac
  printf '%s\n' "$est_c"
}
est_name() { basename "${1%%	*}" .md; }

est_open=$(est_open_plans "$est_repo")
est_branch=$(git -C "$est_repo" symbolic-ref --short -q HEAD || echo "(sin rama)")
est_dirty=no
[ -n "$(git -C "$est_repo" status --porcelain 2>/dev/null)" ] && est_dirty=sí
est_branches=$(git -C "$est_repo" for-each-ref --format='%(refname:short)' \
  refs/heads/feature/ refs/heads/release/ refs/heads/hotfix/ 2>/dev/null | tr '\n' ' ' | sed 's/ $//')

# lista de planes abiertos para el veredicto
est_names=""; est_done=""
if [ -n "$est_open" ]; then
  while IFS= read -r est_l; do
    [ -n "$est_l" ] || continue
    set -- $(est_plan_progress "${est_l%%	*}")
    if [ "$1" -gt 0 ] && [ "$1" -eq "$2" ]; then
      est_done="${est_done:+$est_done, }$(est_name "$est_l")"
    else
      est_names="${est_names:+$est_names, }$(est_name "$est_l")"
    fi
  done <<EOT
$est_open
EOT
fi
est_verdict_open() {
  est_v=""
  [ -n "$est_names" ] && est_v="Estás a mitad de $est_names: termina o pausa antes de empezar otra feature."
  [ -n "$est_done" ] && est_v="${est_v:+$est_v }Todas las casillas de $est_done están marcadas: falta marcar \`ejecutado\`."
  printf '%s' "$est_v"
}
est_next_or_done() { # <archivo> <N> <M>
  if [ "$2" -gt 0 ] && [ "$2" -eq "$3" ]; then printf '%s' 'todas las casillas marcadas — falta marcar `ejecutado`'
  else est_next_step "$1"; fi
}

est_other=""
[ "$est_dirty" = sí ] && est_other="cambios sin commitear"
[ -n "$est_branches" ] && est_other="${est_other:+$est_other; }ramas: $est_branches"

if [ "$est_brief" -eq 1 ]; then
  [ -z "$est_open" ] && [ -z "$est_other" ] && exit 0
  est_out=""
  if [ -n "$est_open" ]; then
    est_n=0
    while IFS= read -r est_l; do
      [ -n "$est_l" ] || continue
      est_n=$((est_n + 1))
      [ "$est_n" -le 2 ] || continue
      est_f=${est_l%%	*}
      set -- $(est_plan_progress "$est_f")
      est_line="Plan $(est_name "$est_f") ($1/$2): $(est_short "$(est_next_or_done "$est_f" "$1" "$2")" 90)"
      est_out="${est_out:+$est_out
}$est_line"
    done <<EOT
$est_open
EOT
    [ "$est_n" -gt 2 ] && est_out="$est_out
(+$((est_n - 2)) más)"
    est_ver=$(est_verdict_open)
  else
    est_ver="Hay algo abierto: $est_other."
  fi
  [ -n "$est_open" ] && [ -n "$est_other" ] && est_out="$est_out
Además: $est_other"
  est_full="$est_out
$est_ver"
  est_full=$(printf '%s' "$est_full" | LC_ALL=C sed '1{/^$/d;}')
  # máximo 3 líneas y 500 bytes (>= caracteres); si no cabe, solo el veredicto
  if [ "$(printf '%s\n' "$est_full" | wc -l | tr -d ' ')" -gt 3 ] || [ "$(printf '%s' "$est_full" | wc -c | tr -d ' ')" -gt 500 ]; then
    est_full=$(est_short "$est_ver" 160)
  fi
  [ "$(printf '%s' "$est_full" | wc -c | tr -d ' ')" -le 500 ] && printf '%s\n' "$est_full"
  exit 0
fi

# --- informe completo ---
echo "## A medias"
if [ -z "$est_open" ]; then
  echo "ninguno"
else
  printf '%s\n' "$est_open" | while IFS= read -r est_l; do
    est_f=${est_l%%	*}
    set -- $(est_plan_progress "$est_f")
    est_flag=""
    [ "$est_l" != "$est_f" ] && est_flag=" [estado incoherente: figura pendiente pero tiene casillas marcadas]"
    echo "- $(est_name "$est_f") ($1/$2)$est_flag"
    if [ "$1" -gt 0 ] && [ "$1" -eq "$2" ]; then
      echo '  todas las casillas marcadas — falta marcar `ejecutado`'
    else
      est_ns=$(est_next_step "$est_f")
      [ -n "$est_ns" ] && echo "  siguiente: $est_ns"
    fi
  done
fi

echo ""
echo "## Git"
echo "rama: $est_branch"
echo "cambios sin commitear: $est_dirty"
echo "ramas feature/release/hotfix locales: ${est_branches:-ninguna}"
est_wt=$(git -C "$est_repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{n++; if (n>1) print substr($0,10)}')
echo "worktrees: $(printf '%s' "${est_wt:-ninguno}" | tr '\n' ' ')"
est_prs=""
if command -v gh >/dev/null 2>&1 && [ -n "$(git -C "$est_repo" remote 2>/dev/null)" ]; then
  est_prs=$(cd "$est_repo" && gh pr list --author @me --state open 2>/dev/null) || est_prs=""
fi
if [ -n "$est_prs" ]; then echo "PR abiertos:"; printf '%s\n' "$est_prs" | sed 's/^/  /'; else echo "PR abiertos: ninguno"; fi

echo ""
echo "## Decisiones pendientes"
if [ -f "$est_repo/DECISIONES.md" ]; then
  est_dec=$(LC_ALL=C awk '
    /^\|/ {
      line = $0; sub(/[ \t]*\|[ \t]*$/, "", line)
      n = split(line, a, "|")
      last = a[n]; gsub(/^[ \t]+|[ \t]+$/, "", last)
      if (last == "pendiente" && n >= 3) {
        id = a[2]; tx = a[3]; gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", tx)
        if (length(tx) > 80) tx = substr(tx, 1, 75) "\001"
        print "- " id ": " tx
      }
    }' "$est_repo/DECISIONES.md" | LC_ALL=C sed "s/$EST_LEADP$EST_MK/$EST_MK/; s/$EST_MK/…/")
fi
echo "${est_dec:-ninguna}"

echo ""
echo "## Sin estado"
est_u=$(est_unstated_count "$est_repo")
if [ "$est_u" -gt 0 ]; then echo "$est_u planes antiguos sin estado; ¿los clasificamos?"; else echo "ninguno"; fi

echo ""
echo "## Veredicto"
if [ -n "$est_open" ]; then
  est_verdict_open; echo
elif [ -n "$est_other" ] || [ -n "$est_prs" ]; then
  [ -n "$est_prs" ] && est_other="${est_other:+$est_other; }PR abiertos"
  echo "Hay algo abierto: $est_other."
else
  echo "No hay nada abierto: puedes empezar una feature."
fi
exit 0
