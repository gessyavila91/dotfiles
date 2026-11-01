#!/bin/sh
# Pruebas de lib/mcp-register.sh con un `claude` falso. HOME y estado son temporales.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
FAIL=0
MCP_REGISTER_DIR="$ROOT/lib"
export MCP_REGISTER_DIR

ok() { echo "ok   $1"; }
ko() { echo "FALLA $1"; FAIL=1; }

# nuevo_entorno: crea TMP con bin/claude falso, HOME, registro de llamadas y estado.
nuevo_entorno() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/bin" "$TMP/casa" "$TMP/estado"
  : > "$TMP/llamadas.log"
  cat > "$TMP/bin/claude" <<'FAKE'
#!/bin/sh
# Falso: registra argv; `mcp get` imprime el formato de la CLI real si el MCP existe.
echo "$*" >> "$FAKE_LOG"
if [ "$1 $2" = "mcp get" ]; then
  [ -f "$FAKE_STATE/$3.txt" ] || exit 1
  cat "$FAKE_STATE/$3.txt"
  exit 0
fi
if [ "$1 $2" = "mcp add-json" ]; then
  # add-json --scope user <nombre> <json>
  node -e '
    const [n, j] = process.argv.slice(1); const c = JSON.parse(j);
    let t = n + ":\n  Scope: User config\n  Type: " + (c.type || "stdio") + "\n";
    if (c.command) t += "  Command: " + c.command + "\n  Args: " + (c.args || []).join(" ") + "\n";
    if (c.url) t += "  URL: " + c.url + "\n";
    require("fs").writeFileSync(process.env.FAKE_STATE + "/" + n + ".txt", t);
  ' "$5" "$6"
  exit 0
fi
exit 0
FAKE
  chmod +x "$TMP/bin/claude"
  FAKE_LOG="$TMP/llamadas.log"; FAKE_STATE="$TMP/estado"
  export FAKE_LOG FAKE_STATE
}

# registrar <env-file> : ejecuta mcp_register con el PATH falso.
registrar() {
  HOME="$TMP/casa" PATH="$TMP/bin:$PATH" sh -c '. "$1"; mcp_register "$2" "$3" macos' sh \
    "$ROOT/lib/mcp-register.sh" "$ROOT/mcp.json" "$1"
}

llamadas_add() { grep -c '^mcp add-json ' "$FAKE_LOG"; }

# mcp_register_always_set
nuevo_entorno
printf 'IDE_MCP=no\n' > "$TMP/m.env"
registrar "$TMP/m.env" >/dev/null 2>&1
if [ "$(llamadas_add)" -eq 2 ] \
  && grep -q '^mcp add-json --scope user codebase-memory-mcp ' "$FAKE_LOG" \
  && grep -q '^mcp add-json --scope user MCP_DOCKER ' "$FAKE_LOG" \
  && grep -qF "$TMP/casa/.local/bin/codebase-memory-mcp" "$FAKE_LOG"; then
  ok mcp_register_always_set
else ko mcp_register_always_set; cat "$FAKE_LOG"; fi
rm -rf "$TMP"

# mcp_register_skips_ide_when_no
nuevo_entorno
printf 'IDE_MCP=no\nPHPSTORM_URL=http://127.0.0.1:1/stream\n' > "$TMP/m.env"
registrar "$TMP/m.env" >/dev/null 2>&1
if ! grep -q 'phpstorm\|pycharm' "$FAKE_LOG"; then ok mcp_register_skips_ide_when_no
else ko mcp_register_skips_ide_when_no; fi
rm -rf "$TMP"

# mcp_register_includes_ide_when_yes (pycharm sin URL: se omite con aviso)
nuevo_entorno
printf 'IDE_MCP=yes\nPHPSTORM_URL=http://127.0.0.1:1111/stream\n' > "$TMP/m.env"
registrar "$TMP/m.env" >"$TMP/out" 2>"$TMP/err"
if grep -q '^mcp add-json --scope user phpstorm {.*http://127.0.0.1:1111/stream' "$FAKE_LOG" \
  && ! grep -q 'add-json.* pycharm ' "$FAKE_LOG" \
  && grep -qi 'pycharm' "$TMP/err" && ! grep -q '{{' "$FAKE_LOG"; then
  ok mcp_register_includes_ide_when_yes
else ko mcp_register_includes_ide_when_yes; cat "$FAKE_LOG" "$TMP/err"; fi
rm -rf "$TMP"

# mcp_register_is_idempotent
nuevo_entorno
printf 'IDE_MCP=yes\nPHPSTORM_URL=http://127.0.0.1:1/stream\nPYCHARM_URL=http://127.0.0.1:2/stream\n' > "$TMP/m.env"
registrar "$TMP/m.env" >/dev/null 2>&1
primero=$(llamadas_add)
registrar "$TMP/m.env" >/dev/null 2>&1
segundo=$(llamadas_add)
# Cambia la URL: debe volver a registrar solo ese MCP.
printf 'IDE_MCP=yes\nPHPSTORM_URL=http://127.0.0.1:9/stream\nPYCHARM_URL=http://127.0.0.1:2/stream\n' > "$TMP/m.env"
registrar "$TMP/m.env" >/dev/null 2>&1
tercero=$(llamadas_add)
if [ "$primero" -eq 4 ] && [ "$segundo" -eq 4 ] && [ "$tercero" -eq 5 ]; then ok mcp_register_is_idempotent
else ko "mcp_register_is_idempotent ($primero $segundo $tercero)"; fi
rm -rf "$TMP"

# mcp_register_without_cli_warns
nuevo_entorno
printf 'IDE_MCP=no\n' > "$TMP/m.env"
rm "$TMP/bin/claude"
# PATH minimo con node y sh, sin claude.
mkdir -p "$TMP/solo"
for b in node sh; do ln -s "$(command -v $b)" "$TMP/solo/$b"; done
HOME="$TMP/casa" PATH="$TMP/solo" /bin/sh -c '. "$1"; mcp_register "$2" "$3" linux' sh \
  "$ROOT/lib/mcp-register.sh" "$ROOT/mcp.json" "$TMP/m.env" >"$TMP/out" 2>"$TMP/err"
rc=$?
if [ "$rc" -eq 0 ] && grep -qi 'claude' "$TMP/err" && [ ! -s "$FAKE_LOG" ]; then ok mcp_register_without_cli_warns
else ko "mcp_register_without_cli_warns (rc=$rc)"; fi
rm -rf "$TMP"

# mcp_register_cli_does_not_consume_stdin (claude falso que lee todo stdin)
nuevo_entorno
sed 's#^echo "\$\*" >> "\$FAKE_LOG"#&; cat >/dev/null#' "$TMP/bin/claude" > "$TMP/bin/c2" && mv "$TMP/bin/c2" "$TMP/bin/claude" && chmod +x "$TMP/bin/claude"
printf 'IDE_MCP=yes\nPHPSTORM_URL=http://127.0.0.1:1/stream\nPYCHARM_URL=http://127.0.0.1:2/stream\n' > "$TMP/m.env"
grep -q 'cat >/dev/null' "$TMP/bin/claude" || ko "preparacion de cli_does_not_consume_stdin"
# MCP_REGISTER_DIR se define despues de cargar el archivo.
(unset MCP_REGISTER_DIR; HOME="$TMP/casa" PATH="$TMP/bin:$PATH" sh -c '. "$1"; MCP_REGISTER_DIR="$4"; mcp_register "$2" "$3" macos' sh \
  "$ROOT/lib/mcp-register.sh" "$ROOT/mcp.json" "$TMP/m.env" "$ROOT/lib" >/dev/null 2>&1)
if [ "$(llamadas_add)" -eq 4 ]; then ok mcp_register_cli_does_not_consume_stdin
else ko "mcp_register_cli_does_not_consume_stdin ($(llamadas_add) de 4)"; fi
rm -rf "$TMP"

# mcp_json_has_no_credentials
if node -e '
  const l = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const bad = [];
  const walk = (v, p) => {
    if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) {
      if (/^(env|headers|token|apiKey|authorization)$/i.test(k)) bad.push(p + k);
      walk(x, p + k + ".");
    } else if (typeof v === "string" && /[A-Za-z0-9_-]{32,}|Bearer |:\/\/[^/@\s]+@/.test(v)) bad.push(p);
  };
  walk(l, "");
  process.exit(bad.length ? 1 : 0);
' "$ROOT/mcp.json"; then ok mcp_json_has_no_credentials
else ko mcp_json_has_no_credentials; fi

exit $FAIL
