#!/bin/sh
# Pruebas de update-versions.sh. Cada caso usa un HOME temporal, un gitconfig global
# temporal, GIT_CONFIG_NOSYSTEM=1, un binario falso y una COPIA del arbol claude-code/
# (el "clon"): nunca se toca el HOME real ni el versions.lock real.
# Interprete: TEST_SH (por defecto sh; p. ej. TEST_SH=dash).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TEST_SH=${TEST_SH:-sh}
FAIL=0

ok() { echo "ok   $1"; }
ko() { echo "FALLA $1"; FAIL=1; }

# nuevo_entorno: HOME con binario falso 0.9.5, plugins instalados y settings.json con
# tres plugins habilitados (a, b) y uno deshabilitado (c).
nuevo_entorno() {
  TMP=$(mktemp -d) || exit 1
  TMP=$(cd "$TMP" && pwd -P) || exit 1
  CASA="$TMP/casa"; CLON="$TMP/clon/claude-code"
  mkdir -p "$CASA/.local/bin" "$CASA/.claude/plugins" "$(dirname "$CLON")"
  cp -R "$ROOT" "$CLON"
  : > "$TMP/gitconfig"
  printf '#!/bin/sh\necho "codebase-memory-mcp 0.9.5 (go1.22.3)"\n' > "$CASA/.local/bin/codebase-memory-mcp"
  chmod +x "$CASA/.local/bin/codebase-memory-mcp"
  cat > "$CASA/.claude/plugins/installed_plugins.json" <<'JSON'
{"version":2,"plugins":{
 "zeta@mk":[{"version":"2.0.0"}],
 "alfa@mk":[{"version":"1.5.0"}],
 "off@mk":[{"version":"9.9.9"}]}}
JSON
  cat > "$CASA/.claude/settings.json" <<'JSON'
{"enabledPlugins":{"zeta@mk":true,"alfa@mk":true,"off@mk":false}}
JSON
  cat > "$CLON/versions.lock" <<'LOCK'
plugin.zeta@mk=1.0.0
codebase-memory-mcp=0.9.0
plugin.off@mk=9.0.0
LOCK
}

entorno() {
  env HOME="$CASA" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 "$@"
}
actualizar() { entorno "$TEST_SH" "$CLON/update-versions.sh" "$@" </dev/null >"$TMP/out" 2>"$TMP/err"; RC=$?; }
doctor() { entorno "$TEST_SH" "$CLON/doctor.sh" </dev/null >"$TMP/dout" 2>"$TMP/derr"; DRC=$?; }

ESPERADO='codebase-memory-mcp=0.9.5
plugin.alfa@mk=1.5.0
plugin.zeta@mk=2.0.0'

# ---------------------------------------------------------------------------
# update_versions_rewrites_lock: claves ordenadas, solo habilitados, valores instalados
nuevo_entorno
actualizar
if [ "$RC" -eq 0 ] && [ "$(cat "$CLON/versions.lock")" = "$ESPERADO" ] \
  && [ -n "$(tail -c1 "$CLON/versions.lock" | od -An -c | grep '\\n')" ]; then ok update_versions_rewrites_lock
else ko "update_versions_rewrites_lock ($RC)"; cat "$CLON/versions.lock" "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_dry_run_writes_nothing: imprime la diferencia y no escribe
nuevo_entorno
a=$(cksum < "$CLON/versions.lock")
actualizar --dry-run
if [ "$RC" -eq 0 ] && [ "$a" = "$(cksum < "$CLON/versions.lock")" ] \
  && grep -q '^[-+]codebase-memory-mcp=0.9.5' "$TMP/out" && grep -q '^-codebase-memory-mcp=0.9.0' "$TMP/out" \
  && [ -z "$(ls "$CLON"/versions.lock.* "$CLON"/.versions* 2>/dev/null)" ]; then ok update_versions_dry_run_writes_nothing
else ko "update_versions_dry_run_writes_nothing ($RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_check_exit_codes: 1 si difiere, 0 si coincide; nunca escribe
nuevo_entorno
a=$(cksum < "$CLON/versions.lock")
actualizar --check; r1=$RC; b=$(cksum < "$CLON/versions.lock")
actualizar; actualizar --check; r2=$RC
if [ "$r1" -eq 1 ] && [ "$a" = "$b" ] && [ "$r2" -eq 0 ]; then ok update_versions_check_exit_codes
else ko "update_versions_check_exit_codes ($r1, $r2)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_skips_disabled_plugins: el deshabilitado sale del lock aunque estuviera
nuevo_entorno
actualizar
if [ "$RC" -eq 0 ] && ! grep -q 'off@mk' "$CLON/versions.lock"; then ok update_versions_skips_disabled_plugins
else ko "update_versions_skips_disabled_plugins ($RC)"; cat "$CLON/versions.lock" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_missing_source_keeps_key: sin binario ni installed_plugins.json las
# claves quedan como estaban (con aviso); sin node falla con 3 y no escribe
nuevo_entorno
rm -f "$CASA/.local/bin/codebase-memory-mcp" "$CASA/.claude/plugins/installed_plugins.json"
actualizar
r1=$RC
l1=$(cat "$CLON/versions.lock")
nuevo_entorno
rm -f "$CASA/.claude/plugins/installed_plugins.json"
actualizar
l2=$(cat "$CLON/versions.lock")
# solo falta el binario
nuevo_entorno
rm -f "$CASA/.local/bin/codebase-memory-mcp"
actualizar
l3=$(cat "$CLON/versions.lock"); r3=$RC
if [ "$r1" -eq 0 ] && grep -q 'codebase-memory-mcp=0.9.0' "$CLON/versions.lock" \
  && printf '%s\n' "$l1" | grep -q '^plugin.zeta@mk=1.0.0$' \
  && grep -q 'aviso' "$TMP/err" \
  && printf '%s\n' "$l2" | grep -q '^codebase-memory-mcp=0.9.5$' && printf '%s\n' "$l2" | grep -q '^plugin.zeta@mk=1.0.0$' \
  && [ "$r3" -eq 0 ] && printf '%s\n' "$l3" | grep -q '^codebase-memory-mcp=0.9.0$' && printf '%s\n' "$l3" | grep -q '^plugin.zeta@mk=2.0.0$'; then
  ok update_versions_missing_source_keeps_key
else ko "update_versions_missing_source_keeps_key ($r1, $r3)"; printf '%s\n--\n%s\n--\n%s\n' "$l1" "$l2" "$l3"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_is_deterministic: dos ejecuciones dan los mismos bytes
nuevo_entorno
actualizar; a=$(cksum < "$CLON/versions.lock"); cp "$CLON/versions.lock" "$TMP/uno"
actualizar; b=$(cksum < "$CLON/versions.lock")
if [ "$a" = "$b" ] && cmp -s "$TMP/uno" "$CLON/versions.lock"; then ok update_versions_is_deterministic
else ko update_versions_is_deterministic; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# update_versions_without_node: sin node sale con 3 y no escribe
nuevo_entorno
a=$(cksum < "$CLON/versions.lock")
mkdir "$TMP/vacio"
env HOME="$CASA" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/vacio" \
  "$(command -v "$TEST_SH")" "$CLON/update-versions.sh" </dev/null >"$TMP/out" 2>"$TMP/err"; RC=$?
if [ "$RC" -eq 3 ] && [ "$a" = "$(cksum < "$CLON/versions.lock")" ]; then ok update_versions_without_node
else ko "update_versions_without_node ($RC)"; cat "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_matches_update_versions: tras update-versions, doctor no ve diferencias de version
nuevo_entorno
doctor; d1=$(grep -c '^diferencia: \(version de\|plugin \)' "$TMP/dout")
actualizar
doctor; d2=$(grep -c '^diferencia: \(version de\|plugin \)' "$TMP/dout")
if [ "$d1" -ge 1 ] && [ "$d2" -eq 0 ]; then ok doctor_matches_update_versions
else ko "doctor_matches_update_versions ($d1, $d2)"; cat "$TMP/dout" "$TMP/derr"; fi
rm -rf "$TMP"

exit $FAIL
