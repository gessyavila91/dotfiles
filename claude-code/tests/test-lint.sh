#!/bin/sh
# Pruebas de claude-code/tools/lint.sh. Cada caso usa un directorio temporal.
HERE=$(cd "$(dirname "$0")" && pwd)
LINT="$HERE/../tools/lint.sh"
FAIL=0

nuevo() { mktemp -d; }

caso() {
  # caso <nombre> <esperado: 0|1> <dir>
  sh "$LINT" "$3" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq "$2" ]; then
    echo "ok   $1"
  else
    echo "FALLA $1 (salida $rc, esperada $2)"
    FAIL=1
  fi
  rm -rf "$3"
}

d=$(nuevo); printf 'ruta=/%s/alguien/x\n' Users > "$d/a.md"
caso lint_rejects_literal_users_path 1 "$d"

d=$(nuevo); printf '{ "a": \n' > "$d/a.json"
caso lint_rejects_invalid_json 1 "$d"

d=$(nuevo); printf 'clave=%s%s\n' ghp_ "abcdefghijklmnopqrstuvwxyz0123456789" > "$d/a.txt"
caso lint_rejects_secret_like_string 1 "$d"

d=$(nuevo); printf '{ "a": 1 }\n' > "$d/a.json"; printf 'ruta=~/x\n' > "$d/a.md"
caso lint_passes_clean_tree 0 "$d"

exit $FAIL
