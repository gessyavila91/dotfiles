#!/bin/sh
# Biblioteca de estado de planes. Sin efectos al hacer `source`.
# POSIX sh: no hay `local`, así que las variables internas llevan prefijo est_.

EST_PLANS_DIR=docs/superpowers/plans

# est_plan_status <archivo> -> pendiente|en_ejecucion|ejecutado|pausado|sin_estado
# Busca desde el título hasta el primer encabezado "## "/"### " (máx. 30 líneas); sin distinguir mayúsculas.
est_plan_status() {
  est_out=$(awk '
    BEGIN { t = 0; n = 0 }
    t == 0 { if ($0 ~ /^# /) t = 1; next }
    /^##+ / { exit }
    { n++; if (n > 30) exit
      l = tolower($0); gsub(/\*/, "", l)
      if (l ~ /^>[ \t]*estado:/) {
        sub(/^>[ \t]*estado:[ \t]*/, "", l)
        if (l ~ /^pendiente/)      { print "pendiente"; exit }
        if (l ~ /^en ejecuci/)     { print "en_ejecucion"; exit }
        if (l ~ /^ejecutado/)      { print "ejecutado"; exit }
        if (l ~ /^pausado/)        { print "pausado"; exit }
      }
    }' "$1" 2>/dev/null)
  echo "${est_out:-sin_estado}"
}

# est_plan_progress <archivo> -> "N M" (casillas marcadas y totales, fuera de bloques de código)
est_plan_progress() {
  awk '
    /^[ \t]*```/ { f = !f; next }
    f { next }
    /^[ \t]*[-*][ \t]+\[[ xX]\]/ { m++; if ($0 ~ /^[ \t]*[-*][ \t]+\[[xX]\]/) d++ }
    END { printf "%d %d\n", d, m }' "$1"
}

# est_next_step <archivo> -> "<título de la ### Task> — <texto del primer - [ ]>"
est_next_step() {
  awk '
    /^[ \t]*```/ { f = !f; next }
    f { next }
    /^### / { t = $0; sub(/^### +/, "", t); next }
    /^[ \t]*[-*][ \t]+\[ \]/ {
      s = $0; sub(/^[ \t]*[-*][ \t]+\[ \][ \t]*/, "", s); gsub(/\*\*/, "", s)
      if (t != "") print t " — " s; else print s
      exit
    }' "$1"
}

# est_plan_files <repo> -> un plan por línea
est_plan_files() {
  for est_pf in "$1/$EST_PLANS_DIR"/*.md; do
    [ -f "$est_pf" ] && printf '%s\n' "$est_pf"
  done
}

# est_is_mixed <archivo> -> éxito si 0 < N < M
est_is_mixed() {
  set -- $(est_plan_progress "$1")
  [ "$1" -gt 0 ] && [ "$1" -lt "$2" ]
}

# est_open_plans <repo>
est_open_plans() {
  est_plan_files "$1" | while IFS= read -r est_f; do
    case $(est_plan_status "$est_f") in
      en_ejecucion) printf '%s\n' "$est_f" ;;
      pendiente) est_is_mixed "$est_f" && printf '%s\tincoherente\n' "$est_f" ;;
      sin_estado) est_is_mixed "$est_f" && printf '%s\n' "$est_f" ;;
    esac
  done
  return 0
}

# est_active_plans <repo> -> solo en_ejecucion
est_active_plans() {
  est_plan_files "$1" | while IFS= read -r est_f; do
    [ "$(est_plan_status "$est_f")" = en_ejecucion ] && printf '%s\n' "$est_f"
  done
  return 0
}

# est_unstated_count <repo> -> planes sin_estado que no están a medias
est_unstated_count() {
  est_c=0
  for est_f in $(est_plan_files "$1" | tr ' ' '?'); do
    est_f=$(printf '%s' "$est_f" | tr '?' ' ')
    if [ "$(est_plan_status "$est_f")" = sin_estado ] && ! est_is_mixed "$est_f"; then
      est_c=$((est_c + 1))
    fi
  done
  echo "$est_c"
}
