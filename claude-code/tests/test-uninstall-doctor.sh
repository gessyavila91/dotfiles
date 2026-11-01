#!/bin/sh
# Pruebas de uninstall.sh y doctor.sh. Cada caso usa un HOME temporal, un gitconfig global
# temporal, GIT_CONFIG_NOSYSTEM=1, un `claude` falso con estado (add-json, remove, list)
# y una COPIA del arbol claude-code/ (el "clon"). Nunca se toca el HOME real.
# Interprete: TEST_SH (por defecto sh; p. ej. TEST_SH=dash).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TEST_SH=${TEST_SH:-sh}
FAIL=0

ok() { echo "ok   $1"; }
ko() { echo "FALLA $1"; FAIL=1; }

nuevo_entorno() {
  TMP=$(mktemp -d) || exit 1
  TMP=$(cd "$TMP" && pwd -P) || exit 1
  CASA="$TMP/casa"; CLON="$TMP/clon/claude-code"
  mkdir -p "$CASA" "$TMP/bin" "$TMP/mcp" "$(dirname "$CLON")"
  cp -R "$ROOT" "$CLON"
  rm -f "$CLON/machine.env"
  : > "$TMP/gitconfig"
  cat > "$TMP/bin/claude" <<'FAKE'
#!/bin/sh
# claude falso con estado en $FAKE_MCP: un archivo por MCP registrado.
D=${FAKE_MCP:?}
case "$1 $2" in
  "mcp get") [ -f "$D/$3" ]; exit $? ;;
  "mcp list") for f in "$D"/*; do [ -f "$f" ] && echo "${f##*/}: registrado - conectado"; done; exit 0 ;;
  "mcp remove") shift 2; [ "$1" = --scope ] && shift 2; rm -f "$D/$1"; exit 0 ;;
  "mcp add-json") shift 2; [ "$1" = --scope ] && shift 2; printf '%s\n' "$2" > "$D/$1"; exit 0 ;;
esac
exit 0
FAKE
  chmod +x "$TMP/bin/claude"
}

entorno() { # ejecuta "$@" con el entorno aislado
  env HOME="$CASA" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    FAKE_MCP="$TMP/mcp" PATH="$TMP/bin:$PATH" "$@"
}
instalar() { entorno "$TEST_SH" "$CLON/install.sh" "$@" </dev/null >"$TMP/out" 2>"$TMP/err"; RC=$?; }
desinstalar() { entorno "$TEST_SH" "$CLON/uninstall.sh" "$@" </dev/null >"$TMP/out" 2>"$TMP/err"; RC=$?; }
doctor() { entorno "$TEST_SH" "$CLON/doctor.sh" "$@" </dev/null >"$TMP/out" 2>"$TMP/err"; RC=$?; }

# huella <dir>: tipo, ruta, destino del enlace o suma del contenido (sin Respaldos).
huella() {
  ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
      case $p in ./Respaldos|./Respaldos/*) continue ;; esac
      if [ -L "$p" ]; then printf 'L %s %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'D %s\n' "$p"
      else printf 'F %s %s\n' "$p" "$(cksum < "$p")"
      fi
    done ) | sed -e "s|$TMP|TMP|g"
}
estado_total() { huella "$CASA"; echo ==; huella "$CLON"; echo ==; cat "$TMP/gitconfig"; }

# ---------------------------------------------------------------------------
# uninstall_restores_previous_state
nuevo_entorno
mkdir -p "$CASA/.claude/skills/propia"
cp -R "$CLON/skills/estado" "$CASA/.claude/skills/estado"
echo 'contenido propio' > "$CASA/.claude/skills/propia/SKILL.md"
echo '{"model":"mio"}' > "$CASA/.claude/settings.json"
echo 'nota' > "$CASA/.claude/otro.txt"
printf '[user]\n\tname = prueba\n' > "$TMP/gitconfig"
antes=$(huella "$CASA")
gc_antes=$(cat "$TMP/gitconfig")
instalar --adopt --non-interactive
rc_i=$RC
desinstalar
despues=$(huella "$CASA")
bien=1
[ "$rc_i" -eq 0 ] || { bien=0; echo "  install rc=$rc_i"; cat "$TMP/err"; }
[ "$RC" -eq 0 ] || { bien=0; echo "  uninstall rc=$RC"; cat "$TMP/err"; }
[ "$antes" = "$despues" ] || { bien=0; printf '%s\n' "$antes" > "$TMP/a"; printf '%s\n' "$despues" | diff "$TMP/a" - | head -20; }
[ "$(cat "$TMP/gitconfig")" = "$gc_antes" ] || { bien=0; echo "  gitconfig"; cat "$TMP/gitconfig"; }
[ -f "$CLON/skills/propia/SKILL.md" ] || { bien=0; echo "  lo adoptado se borro del repo"; }
[ -n "$(ls -d "$CASA"/Respaldos/p4-* 2>/dev/null)" ] || { bien=0; echo "  el respaldo ya no esta"; }
[ ! -e "$CASA/.claude/.p4-manifest" ] || { bien=0; echo "  manifiesto sigue"; }
[ "$bien" -eq 1 ] && ok uninstall_restores_previous_state || ko uninstall_restores_previous_state
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_keeps_unknown_files
nuevo_entorno
instalar --non-interactive
echo x > "$CASA/.claude/notas.txt"
mkdir -p "$CASA/.claude/skills/ajena"; echo y > "$CASA/.claude/skills/ajena/z"
echo h > "$CASA/.config/git/hooks/mio.sh"
desinstalar
bien=1
[ "$RC" -eq 0 ] || { bien=0; echo "  rc=$RC"; cat "$TMP/err"; }
[ -f "$CASA/.claude/notas.txt" ] && [ -f "$CASA/.claude/skills/ajena/z" ] && [ -f "$CASA/.config/git/hooks/mio.sh" ] \
  || { bien=0; echo "  se perdio un archivo ajeno"; }
[ ! -e "$CASA/.claude/CLAUDE.md" ] && [ ! -L "$CASA/.claude/CLAUDE.md" ] || { bien=0; echo "  quedo CLAUDE.md"; }
[ ! -L "$CASA/.claude/skills/estado" ] || { bien=0; echo "  quedo enlace de skill"; }
[ ! -L "$CASA/.config/git/hooks/lib.sh" ] || { bien=0; echo "  quedo enlace de git hook"; }
[ "$(git config -f "$TMP/gitconfig" --get core.hooksPath)" = "" ] || { bien=0; echo "  core.hooksPath sigue"; }
[ "$bien" -eq 1 ] && ok uninstall_keeps_unknown_files || ko uninstall_keeps_unknown_files
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_keeps_foreign_hookspath: core.hooksPath ajeno no se toca
nuevo_entorno
git config -f "$TMP/gitconfig" core.hooksPath "$CASA/otros-hooks"
instalar --non-interactive
desinstalar
if [ "$RC" -eq 0 ] && [ "$(git config -f "$TMP/gitconfig" --get core.hooksPath)" = "$CASA/otros-hooks" ]; then ok uninstall_keeps_foreign_hookspath
else ko "uninstall_keeps_foreign_hookspath (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_is_idempotent: la segunda vez no hace nada (sale 1: nada instalado)
nuevo_entorno
instalar --non-interactive
desinstalar
primero=$RC
a=$(estado_total)
desinstalar
b=$(estado_total)
if [ "$primero" -eq 0 ] && [ "$RC" -eq 1 ] && [ "$a" = "$b" ]; then ok uninstall_is_idempotent
else ko "uninstall_is_idempotent ($primero, $RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_without_manifest_exits_1
nuevo_entorno
a=$(estado_total)
desinstalar
if [ "$RC" -eq 1 ] && cat "$TMP/err" "$TMP/out" | grep -qi 'nada instalado' && [ "$a" = "$(estado_total)" ]; then ok uninstall_without_manifest_exits_1
else ko "uninstall_without_manifest_exits_1 (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_dry_run_changes_nothing
nuevo_entorno
mkdir -p "$CASA/.claude"; echo '{"a":1}' > "$CASA/.claude/settings.json"
instalar --non-interactive
a=$(estado_total)
desinstalar --dry-run
if [ "$RC" -eq 0 ] && [ "$a" = "$(estado_total)" ] && grep -q 'simulacion' "$TMP/out"; then ok uninstall_dry_run_changes_nothing
else ko "uninstall_dry_run_changes_nothing (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_refuses_inconsistent_state: linea desconocida / otro clon -> 2 sin tocar nada
nuevo_entorno
instalar --non-interactive
printf 'cosa\t%s/x\t\n' "$CASA" >> "$CASA/.claude/.p4-manifest"
a=$(estado_total)
desinstalar
r1=$RC
[ "$a" = "$(estado_total)" ] || r1=99
rm -rf "$TMP"
nuevo_entorno
instalar --non-interactive
printf 'link\t%s/.claude/CLAUDE.md\t/otro/clon/CLAUDE.md\n' "$CASA" >> "$CASA/.claude/.p4-manifest"
desinstalar
r2=$RC
if [ "$r1" -eq 2 ] && [ "$r2" -eq 2 ] && [ -L "$CASA/.claude/CLAUDE.md" ]; then ok uninstall_refuses_inconsistent_state
else ko "uninstall_refuses_inconsistent_state ($r1, $r2)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_clean_after_install
nuevo_entorno
instalar --non-interactive
doctor
if [ "$RC" -eq 0 ]; then ok doctor_clean_after_install; else ko "doctor_clean_after_install (rc=$RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_detects_drift: un plugin activado a mano en settings.json
nuevo_entorno
instalar --non-interactive
node -e '
  const fs = require("fs"); const f = process.argv[1];
  const j = JSON.parse(fs.readFileSync(f, "utf8"));
  j.enabledPlugins = Object.assign({}, j.enabledPlugins, { "manual@alguien": true });
  fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n");' "$CASA/.claude/settings.json"
doctor
if [ "$RC" -eq 1 ] && grep -q 'settings.json' "$TMP/out"; then ok doctor_detects_drift
else ko "doctor_detects_drift (rc=$RC)"; cat "$TMP/out"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_detects_broken_link, y archivo regular o enlace ajeno en lugar del enlace
nuevo_entorno
instalar --non-interactive
rm -rf "$CLON/skills/estado"
doctor
r1=$RC; roto=$(grep -c 'roto' "$TMP/out")
rm -f "$CASA/.claude/CLAUDE.md"; echo copia > "$CASA/.claude/CLAUDE.md"
ln -sf /tmp "$CASA/.config/git/hooks/lib.sh"
doctor
if [ "$r1" -eq 1 ] && [ "$roto" -ge 1 ] && grep -q 'estado' "$TMP/out" && [ "$RC" -eq 1 ] \
   && grep -q 'CLAUDE.md' "$TMP/out" && grep -q 'lib.sh' "$TMP/out"; then ok doctor_detects_broken_link
else ko "doctor_detects_broken_link ($r1, $RC)"; cat "$TMP/out"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_detects_version_mismatch (y acepta versiones iguales)
nuevo_entorno
instalar --non-interactive
mkdir -p "$CASA/.local/bin" "$CASA/.claude/plugins"
printf '#!/bin/sh\necho "codebase-memory-mcp 0.8.0"\n' > "$CASA/.local/bin/codebase-memory-mcp"
chmod +x "$CASA/.local/bin/codebase-memory-mcp"
doctor
r1=$RC; g1=$(grep -c 'codebase-memory-mcp' "$TMP/out")
printf '#!/bin/sh\necho "codebase-memory-mcp 0.9.0 (go1.22.3)"\n' > "$CASA/.local/bin/codebase-memory-mcp"
cat > "$CASA/.claude/plugins/installed_plugins.json" <<'JSON'
{"version":2,"plugins":{
 "gitkraken-hooks@gitkraken":[{"version":"3.1.71"}],
 "notification@paulodiovani":[{"version":"2.0.0"}],
 "superpowers@claude-plugins-official":[{"version":"7.0.0"}],
 "savvy-progress@claude-kit":[{"version":"1.2.1"}],
 "filetree@claude-code-filetree":[{"version":"0.4.1"}]}}
JSON
doctor
r2=$RC
sed 's/"7.0.0"/"6.9.0"/' "$CASA/.claude/plugins/installed_plugins.json" > "$TMP/p.json"
mv "$TMP/p.json" "$CASA/.claude/plugins/installed_plugins.json"
doctor
if [ "$r1" -eq 1 ] && [ "$g1" -ge 1 ] && [ "$r2" -eq 0 ] && [ "$RC" -eq 1 ] && grep -q 'superpowers' "$TMP/out"; then ok doctor_detects_version_mismatch
else ko "doctor_detects_version_mismatch ($r1, $g1, $r2, $RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_detects_missing_mcp
nuevo_entorno
instalar --non-interactive
rm -f "$TMP/mcp/MCP_DOCKER"
doctor
if [ "$RC" -eq 1 ] && grep -q 'MCP_DOCKER' "$TMP/out"; then ok doctor_detects_missing_mcp
else ko "doctor_detects_missing_mcp (rc=$RC)"; cat "$TMP/out"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_is_read_only: con diferencias y sin ellas el estado no cambia
nuevo_entorno
instalar --non-interactive
a=$(estado_total)
doctor; r1=$RC
echo '{"x":1}' > "$CASA/.claude/settings.json"
rm -f "$CASA/.claude/skills/estado"
b=$(estado_total)
doctor; r2=$RC
if [ "$r1" -eq 0 ] && [ "$r2" -eq 1 ] && [ "$b" = "$(estado_total)" ] && [ "$a" != "$b" ]; then ok doctor_is_read_only
else ko "doctor_is_read_only ($r1, $r2)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_keeps_preexisting_identical_settings: ya era identico al generado -> se conserva
nuevo_entorno
instalar --non-interactive
cp "$CASA/.claude/settings.json" "$TMP/s.json"
desinstalar
mkdir -p "$CASA/.claude"; cp "$TMP/s.json" "$CASA/.claude/settings.json"
instalar --non-interactive
grep -q "^settings	$CASA/.claude/settings.json	preexistente\$" "$CASA/.claude/.p4-manifest"; m=$?
instalar --non-interactive
grep -c '^settings	' "$CASA/.claude/.p4-manifest" | grep -qx 1; m2=$?
desinstalar
if [ "$m" -eq 0 ] && [ "$m2" -eq 0 ] && [ "$RC" -eq 0 ] && cmp -s "$TMP/s.json" "$CASA/.claude/settings.json" \
   && grep -q 'se conserva' "$TMP/out"; then ok uninstall_keeps_preexisting_identical_settings
else ko "uninstall_keeps_preexisting_identical_settings ($m, $m2, $RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_duplicate_backup_paths_exit_2: misma ruta en dos respaldos con contenido distinto
nuevo_entorno
mkdir -p "$CASA/.claude/skills/propia"; echo v1 > "$CASA/.claude/skills/propia/SKILL.md"
instalar --adopt --non-interactive
B2="$CASA/Respaldos/p4-20990101-000000-AAAAAA"
mkdir -p "$B2/.claude/skills/propia"; echo v2 > "$B2/.claude/skills/propia/SKILL.md"
echo "backup=$B2" >> "$CASA/.claude/.p4-manifest"
a=$(estado_total)
desinstalar
if [ "$RC" -eq 2 ] && [ "$a" = "$(estado_total)" ] && [ -f "$CASA/.claude/.p4-manifest" ] && grep -q 'dos respaldos' "$TMP/err"; then ok uninstall_duplicate_backup_paths_exit_2
else ko "uninstall_duplicate_backup_paths_exit_2 ($RC)"; cat "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_warns_settings_changes y settings borrado a mano
nuevo_entorno
mkdir -p "$CASA/.claude"; echo '{"a":1}' > "$CASA/.claude/settings.json"
instalar --non-interactive
echo '{"cambiado":1}' > "$CASA/.claude/settings.json"
desinstalar
r1=$RC
bien=1
[ "$(cat "$CASA/.claude/settings.json")" = '{"a":1}' ] || { bien=0; echo "  no se restauro"; }
grep -q 'resumen de avisos' "$TMP/out" && grep -q 'cambios posteriores' "$TMP/out" || { bien=0; echo "  sin resumen"; }
ls "$CASA"/Respaldos/p4-*/settings.json.p4-previo-* >/dev/null 2>&1 || { bien=0; echo "  sin copia previa"; }
rm -rf "$TMP"
nuevo_entorno
mkdir -p "$CASA/.claude"; echo '{"a":1}' > "$CASA/.claude/settings.json"
instalar --non-interactive
rm -f "$CASA/.claude/settings.json"
desinstalar
[ "$RC" -eq 0 ] && [ ! -e "$CASA/.claude/settings.json" ] && grep -q 'no se restaura en silencio' "$TMP/out" || { bien=0; echo "  ausente ($RC)"; cat "$TMP/out"; }
[ "$r1" -eq 0 ] && [ "$bien" -eq 1 ] && ok uninstall_warns_settings_changes || ko "uninstall_warns_settings_changes ($r1)"
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_compares_mcp_names_literally: "mi.mcp" no coincide con "miXmcp"
nuevo_entorno
node -e '
  const fs = require("fs"); const f = process.argv[1];
  const l = JSON.parse(fs.readFileSync(f, "utf8"));
  l.push({ name: "mi.mcp", when: "always", config: { type: "stdio", command: "true", args: [] } });
  fs.writeFileSync(f, JSON.stringify(l, null, 2) + "\n");' "$CLON/mcp.json"
instalar --non-interactive
doctor; r0=$RC
rm -f "$TMP/mcp/mi.mcp"; : > "$TMP/mcp/miXmcp"
doctor
if [ "$r0" -eq 0 ] && [ "$RC" -eq 1 ] && grep -q "mi.mcp" "$TMP/out"; then ok doctor_compares_mcp_names_literally
else ko "doctor_compares_mcp_names_literally ($r0, $RC)"; cat "$TMP/out"; fi
rm -rf "$TMP"

# doctor_ignores_adopt_ignore_paths: skills/synced (adopt-ignore) no es diferencia para
# doctor, y uninstall lo deja en su sitio sin quejarse.
nuevo_entorno
instalar --non-interactive
doctor; r0=$RC
mkdir -p "$CASA/.claude/skills/synced/pdf"; echo cache > "$CASA/.claude/skills/synced/pdf/SKILL.md"
doctor; r1=$RC; o1=$(cat "$TMP/out")
desinstalar; r2=$RC
if [ "$r0" -eq 0 ] && [ "$r1" -eq 0 ] && ! printf '%s\n' "$o1" | grep -q synced \
  && [ "$r2" -eq 0 ] && [ "$(cat "$CASA/.claude/skills/synced/pdf/SKILL.md" 2>/dev/null)" = cache ]; then
  ok doctor_ignores_adopt_ignore_paths
else ko "doctor_ignores_adopt_ignore_paths ($r0 $r1 $r2)"; printf '%s\n' "$o1"; cat "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_ignores_git_hooks_not_in_manifest: carpeta de hooks ajena, el instalador la omitio
nuevo_entorno
mkdir -p "$CASA/.config/git/hooks"; echo '#!/bin/sh' > "$CASA/.config/git/hooks/pre-commit"
instalar --non-interactive
doctor
if [ "$RC" -eq 0 ] && ! grep -q '^diferencia' "$TMP/out" && grep -q 'hooks de git no instalados' "$TMP/err"; then ok doctor_ignores_git_hooks_not_in_manifest
else ko "doctor_ignores_git_hooks_not_in_manifest ($RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# doctor_shows_relative_link_target: se muestra el destino del enlace tal cual
nuevo_entorno
instalar --non-interactive
rm -f "$CASA/.claude/CLAUDE.md"; ln -s rel-destino "$CASA/.claude/CLAUDE.md"
echo x > "$CASA/.claude/rel-destino"
rm -f "$CASA/.config/git/hooks/lib.sh"; ln -s dispatch "$CASA/.config/git/hooks/lib.sh"
doctor
if [ "$RC" -eq 1 ] && grep -q 'CLAUDE.md apunta a rel-destino' "$TMP/out" && grep -q 'lib.sh -> dispatch' "$TMP/out"; then ok doctor_shows_relative_link_target
else ko "doctor_shows_relative_link_target ($RC)"; cat "$TMP/out"; fi
rm -rf "$TMP"

# ===========================================================================
# Modo copia (--copy; Windows)

# uninstall_copy_mode_restores_previous_state: como en modo enlace, y ademas una
# actualizacion intermedia (copia previa en p4-copias-previas) que no se restaura.
nuevo_entorno
mkdir -p "$CASA/.claude/skills/propia"
cp -R "$CLON/skills/estado" "$CASA/.claude/skills/estado"
echo 'contenido propio' > "$CASA/.claude/skills/propia/SKILL.md"
echo '{"model":"mio"}' > "$CASA/.claude/settings.json"
echo 'nota' > "$CASA/.claude/otro.txt"
printf '[user]\n\tname = prueba\n' > "$TMP/gitconfig"
antes=$(huella "$CASA")
gc_antes=$(cat "$TMP/gitconfig")
instalar --copy --adopt --non-interactive; rc_i=$RC
echo "# regla nueva" >> "$CLON/CLAUDE.md"
instalar --copy --non-interactive; rc_i2=$RC
a_dry=$(estado_total)
desinstalar --dry-run; rc_dry=$RC
[ "$a_dry" = "$(estado_total)" ] || rc_dry=99
desinstalar
despues=$(huella "$CASA")
bien=1
[ "$rc_i" -eq 0 ] && [ "$rc_i2" -eq 0 ] || { bien=0; echo "  install rc=$rc_i $rc_i2"; cat "$TMP/err"; }
[ "$rc_dry" -eq 0 ] || { bien=0; echo "  dry-run rc=$rc_dry"; }
[ "$RC" -eq 0 ] || { bien=0; echo "  uninstall rc=$RC"; cat "$TMP/err"; }
[ "$antes" = "$despues" ] || { bien=0; printf '%s\n' "$antes" > "$TMP/a"; printf '%s\n' "$despues" | diff "$TMP/a" - | head -20; }
[ "$(cat "$TMP/gitconfig")" = "$gc_antes" ] || { bien=0; echo "  gitconfig"; cat "$TMP/gitconfig"; }
[ -f "$CLON/skills/propia/SKILL.md" ] || { bien=0; echo "  lo adoptado se borro del repo"; }
[ ! -e "$CASA/.claude/.p4-manifest" ] || { bien=0; echo "  manifiesto sigue"; }
desinstalar
[ "$RC" -eq 1 ] || { bien=0; echo "  segunda vez rc=$RC"; }
[ "$bien" -eq 1 ] && ok uninstall_copy_mode_restores_previous_state || ko uninstall_copy_mode_restores_previous_state
rm -rf "$TMP"

# uninstall_copy_mode_keeps_edited_copy: una copia con cambios a mano se conserva y se avisa;
# las demas se quitan.
nuevo_entorno
instalar --copy --non-interactive; rc_i=$RC
echo "mi cambio" >> "$CASA/.claude/CLAUDE.md"
echo "otro cambio" >> "$CASA/.claude/skills/estado/SKILL.md"
cp "$CASA/.claude/CLAUDE.md" "$TMP/editado"
desinstalar
bien=1
[ "$rc_i" -eq 0 ] && [ "$RC" -eq 0 ] || { bien=0; echo "  rc $rc_i $RC"; cat "$TMP/err"; }
cmp -s "$CASA/.claude/CLAUDE.md" "$TMP/editado" || { bien=0; echo "  se perdio la copia editada"; }
grep -q 'otro cambio' "$CASA/.claude/skills/estado/SKILL.md" 2>/dev/null || { bien=0; echo "  se perdio la skill editada"; }
grep -q 'resumen de avisos' "$TMP/out" && grep -q "CLAUDE.md" "$TMP/out" || { bien=0; echo "  sin aviso"; cat "$TMP/out"; }
[ ! -e "$CASA/.claude/hooks/gitflow-guard.sh" ] && [ ! -e "$CASA/.config/git/hooks/pre-push" ] || { bien=0; echo "  quedaron copias sin editar"; }
[ ! -e "$CASA/.claude/.p4-manifest" ] || { bien=0; echo "  manifiesto sigue"; }
[ "$bien" -eq 1 ] && ok uninstall_copy_mode_keeps_edited_copy || ko uninstall_copy_mode_keeps_edited_copy
rm -rf "$TMP"

# doctor_copy_mode_clean_after_install
nuevo_entorno
instalar --copy --non-interactive
doctor
if [ "$RC" -eq 0 ] && ! grep -q '^diferencia' "$TMP/out"; then ok doctor_copy_mode_clean_after_install
else ko "doctor_copy_mode_clean_after_install (rc=$RC)"; cat "$TMP/out" "$TMP/err"; fi
rm -rf "$TMP"

# doctor_copy_mode_detects_edited_copy: copia editada, copia que falta y repo cambiado.
nuevo_entorno
instalar --copy --non-interactive
echo "mi cambio" >> "$CASA/.claude/CLAUDE.md"
doctor; r1=$RC; o1=$(cat "$TMP/out")
rm -f "$CASA/.config/git/hooks/pre-push"
echo "linea nueva" >> "$CLON/skills/estado/SKILL.md"
a=$(estado_total)
doctor
if [ "$r1" -eq 1 ] && printf '%s\n' "$o1" | grep -q 'CLAUDE.md.*difiere' \
  && [ "$RC" -eq 1 ] && grep -q 'pre-push' "$TMP/out" && grep -q 'skills/estado.*difiere' "$TMP/out" \
  && [ "$a" = "$(estado_total)" ]; then ok doctor_copy_mode_detects_edited_copy
else ko "doctor_copy_mode_detects_edited_copy ($r1, $RC)"; printf '%s\n' "$o1"; cat "$TMP/out"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# uninstall_from_old_clone_still_works: tras negarse la instalacion desde otro clon, el
# clon antiguo desinstala y despues el nuevo instala; doctor desde el nuevo avisa antes.
nuevo_entorno
instalar --non-interactive; r0=$RC
CLON_A=$CLON; CLON_B="$TMP/clon2/claude-code"
mkdir -p "$TMP/clon2"; cp -R "$ROOT" "$CLON_B"; rm -f "$CLON_B/machine.env"
CLON=$CLON_B; instalar --non-interactive; r1=$RC
doctor; rd=$RC; od=$(cat "$TMP/out")
desinstalar; ru=$RC; eu=$(cat "$TMP/err")
CLON=$CLON_A; desinstalar; r2=$RC
CLON=$CLON_B; instalar --non-interactive; r3=$RC
if [ "$r0" -eq 0 ] && [ "$r1" -eq 2 ] && [ "$rd" -eq 1 ] && printf '%s\n' "$od" | grep -q 'otro clon' \
  && [ "$ru" -eq 2 ] && printf '%s\n' "$eu" | grep -q 'clon antiguo' \
  && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ] && [ -L "$CASA/.claude/CLAUDE.md" ] \
  && [ "$(readlink "$CASA/.claude/CLAUDE.md")" = "$CLON_B/CLAUDE.md" ]; then ok uninstall_from_old_clone_still_works
else ko "uninstall_from_old_clone_still_works ($r0 $r1 $rd $ru $r2 $r3)"; printf '%s\n' "$od"; cat "$TMP/err"; fi
rm -rf "$TMP"

exit $FAIL
