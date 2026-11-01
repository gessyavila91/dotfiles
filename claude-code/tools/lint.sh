#!/bin/sh
# lint.sh: valida el arbol de claude-code/ (o el directorio dado).
# Falla (salida 1) si encuentra JSON invalido, rutas literales de usuario
# (del directorio personal de macOS o Linux) o cadenas con forma de secreto.
# Los patrones se escriben con corchetes para que este archivo no se detecte a si mismo.
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
BAD=0
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

if [ ! -d "$DIR" ]; then
  echo "lint: no existe el directorio $DIR" >&2
  exit 2
fi

# 1. JSON valido (requiere node >= 18)
if find "$DIR" -type f -name '*.json' | grep . >/dev/null 2>&1; then
  if ! command -v node >/dev/null 2>&1; then
    echo "lint: falta node para validar JSON" >&2
    exit 2
  fi
  find "$DIR" -type f -name '*.json' > "$LIST"
  node -e '
    const fs = require("fs");
    let bad = 0;
    for (const f of fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean)) {
      try { JSON.parse(fs.readFileSync(f, "utf8")); }
      catch (e) { console.log("JSON invalido: " + f); bad = 1; }
    }
    process.exit(bad);
  ' "$LIST" || BAD=1
fi

# 2. Rutas literales de usuario
if grep -rInE '/[U]sers/[^/<[:space:]$]|/[h]ome/[A-Za-z0-9_.-]+/' "$DIR"; then
  echo "lint: ruta literal de usuario (usar ~ o \$HOME)"; BAD=1
fi

# 3. Cadenas con forma de secreto
if grep -rInE '(^|[^A-Za-z0-9])s[k]-[A-Za-z0-9_-]{16,}|g[h]p_[A-Za-z0-9]{20,}|x[o]x[bp]-[A-Za-z0-9-]{10,}|A[K]IA[0-9A-Z]{16}|-----BEG[I]N' "$DIR"; then
  echo "lint: posible secreto"; BAD=1
fi

[ "$BAD" -eq 0 ] && echo "lint: ok"
exit $BAD
