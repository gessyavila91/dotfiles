#!/bin/sh
# Pruebas de install.sh. Cada caso usa un HOME temporal, un gitconfig global temporal,
# GIT_CONFIG_NOSYSTEM=1, un `claude` falso al frente del PATH y una COPIA del arbol
# claude-code/ (el "clon"), para que adoptar o crear machine.env no toque el repo real.
# Interprete del instalador: TEST_SH (por defecto sh; p. ej. TEST_SH=dash).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TEST_SH=${TEST_SH:-sh}
FAIL=0

ok() { echo "ok   $1"; }
ko() { echo "FALLA $1"; FAIL=1; }

# nuevo_entorno: TMP con casa/, clon/claude-code (copia), bin/claude falso y gitconfig.
nuevo_entorno() {
  TMP=$(mktemp -d) || exit 1
  TMP=$(cd "$TMP" && pwd -P) || exit 1
  mkdir -p "$TMP/casa" "$TMP/bin" "$TMP/clon"
  cp -R "$ROOT" "$TMP/clon/claude-code"
  rm -f "$TMP/clon/claude-code/machine.env"
  CLON="$TMP/clon/claude-code"
  CASA="$TMP/casa"
  : > "$TMP/gitconfig"
  : > "$TMP/llamadas.log"
  cat > "$TMP/bin/claude" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
[ "$1 $2" = "mcp get" ] && exit 1
exit 0
FAKE
  chmod +x "$TMP/bin/claude"
}

# instalar [args...]: ejecuta el instalador del clon; deja RC, $TMP/out y $TMP/err.
instalar() {
  env HOME="$CASA" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    FAKE_LOG="$TMP/llamadas.log" PATH="$TMP/bin:$PATH" \
    "$TEST_SH" "$CLON/install.sh" "$@" </dev/null >"$TMP/out" 2>"$TMP/err"
  RC=$?
}

# huella <dir>: tipo, ruta relativa, destino de enlace o suma del contenido. Las rutas
# del entorno (HOME, clon) y los nombres con fecha de respaldo se normalizan.
huella() {
  ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'L %s %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'D %s\n' "$p"
      else printf 'F %s %s\n' "$p" "$(sed -e "s|$TMP|TMP|g" -e 's/p4-[0-9]\{8\}-[0-9]\{6\}-[A-Za-z0-9]\{6\}/p4-RESP/g' "$p" | cksum)"
      fi
    done ) | sed -e "s|$TMP|TMP|g" -e 's/p4-[0-9]\{8\}-[0-9]\{6\}-[A-Za-z0-9]\{6\}/p4-RESP/g' \
      -e 's/p4-bak-[0-9]\{8\}-[0-9]\{6\}/p4-bak-TS/g'
}

# estado_total: casa, clon y gitconfig.
estado_total() {
  huella "$CASA"; echo ==; huella "$CLON"; echo ==; cat "$TMP/gitconfig"
}

# es_enlace_a <destino> <origen>
es_enlace_a() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

respaldos() { ls -d "$CASA"/Respaldos/p4-* 2>/dev/null; }

# ---------------------------------------------------------------------------
# install_fresh_creates_links_and_settings
nuevo_entorno
instalar --non-interactive
bien=1
[ "$RC" -eq 0 ] || { bien=0; echo "  rc=$RC"; cat "$TMP/err"; }
es_enlace_a "$CASA/.claude/CLAUDE.md" "$CLON/CLAUDE.md" || { bien=0; echo "  CLAUDE.md"; }
for s in "$CLON"/skills/*; do
  es_enlace_a "$CASA/.claude/skills/${s##*/}" "$s" || { bien=0; echo "  skill ${s##*/}"; }
done
for h in "$CLON"/hooks/*; do
  es_enlace_a "$CASA/.claude/hooks/${h##*/}" "$h" || { bien=0; echo "  hook ${h##*/}"; }
done
es_enlace_a "$CASA/.claude/themes/dracula.json" "$CLON/themes/dracula.json" || { bien=0; echo "  tema"; }
while IFS= read -r n; do
  es_enlace_a "$CASA/.config/git/hooks/$n" "$CLON/git-hooks/dispatch" || { bien=0; echo "  git hook $n"; }
done < "$CLON/git-hooks/NAMES"
es_enlace_a "$CASA/.config/git/hooks/lib.sh" "$CLON/git-hooks/lib.sh" || { bien=0; echo "  lib.sh"; }
[ "$(GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 git config --global --get core.hooksPath)" = "$CASA/.config/git/hooks" ] \
  || { bien=0; echo "  core.hooksPath"; }
s="$CASA/.claude/settings.json"
{ [ -f "$s" ] && [ ! -L "$s" ] && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$s" \
  && ! grep -q '{{HOME}}' "$s"; } || { bien=0; echo "  settings.json"; }
grep -qx 'IDE_MCP=no' "$CLON/machine.env" 2>/dev/null || { bien=0; echo "  machine.env"; }
grep -q 'machine.env' "$TMP/out" || { bien=0; echo "  no avisa de machine.env creado"; }
m="$CASA/.claude/.p4-manifest"
{ [ -f "$m" ] && grep -q "^link	$CASA/.claude/CLAUDE.md	$CLON/CLAUDE.md\$" "$m" \
  && grep -q "^settings	$CASA/.claude/settings.json" "$m"; } || { bien=0; echo "  manifiesto"; }
grep -q '^mcp add-json ' "$TMP/llamadas.log" || { bien=0; echo "  mcp_register no llamado"; }
[ -z "$(respaldos)" ] || { bien=0; echo "  respaldo innecesario"; }
[ "$bien" -eq 1 ] && ok install_fresh_creates_links_and_settings || ko install_fresh_creates_links_and_settings
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_is_idempotent
nuevo_entorno
instalar --non-interactive
antes=$(estado_total)
instalar --non-interactive
rc2=$RC
despues=$(estado_total)
if [ "$rc2" -eq 0 ] && [ "$antes" = "$despues" ]; then ok install_is_idempotent
else ko "install_is_idempotent (rc=$rc2)"; printf '%s\n' "$antes" > "$TMP/a"; printf '%s\n' "$despues" | diff "$TMP/a" - | head -20; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_backs_up_before_changing: una skill ajena identica, con --adopt.
nuevo_entorno
mkdir -p "$CASA/.claude/skills"
cp -R "$CLON/skills/estado" "$CASA/.claude/skills/estado"
instalar --adopt --non-interactive
r=$(respaldos)
bien=1
[ "$RC" -eq 0 ] || { bien=0; echo "  rc=$RC"; cat "$TMP/err"; }
[ "$(printf '%s\n' "$r" | grep -c .)" -eq 1 ] || { bien=0; echo "  respaldos: $r"; }
case ${r##*/} in p4-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-??????) ;; *) bien=0; echo "  nombre $r";; esac
[ "$(ls -ld "$r" | cut -c1-10)" = "drwx------" ] || { bien=0; echo "  permisos"; }
diff -r "$r/.claude/skills/estado" "$CLON/skills/estado" >/dev/null || { bien=0; echo "  contenido respaldado"; }
es_enlace_a "$CASA/.claude/skills/estado" "$CLON/skills/estado" || { bien=0; echo "  enlace"; }
grep -qx "backup=$r" "$CASA/.claude/.p4-manifest" || { bien=0; echo "  backup= en manifiesto"; }
[ "$bien" -eq 1 ] && ok install_backs_up_before_changing || ko install_backs_up_before_changing
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_refuses_existing_foreign_file
nuevo_entorno
mkdir -p "$CASA/.claude"
echo "reglas de otra persona" > "$CASA/.claude/CLAUDE.md"
antes=$(estado_total)
instalar --non-interactive
if [ "$RC" -eq 2 ] && [ "$antes" = "$(estado_total)" ] && grep -q 'reglas de otra persona' "$TMP/out" "$TMP/err"; then
  ok install_refuses_existing_foreign_file
else ko "install_refuses_existing_foreign_file (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_refuses_foreign_symlink: enlace a otro clon, aun con el mismo contenido.
nuevo_entorno
mkdir -p "$CASA/.claude" "$TMP/otro"
cp "$CLON/CLAUDE.md" "$TMP/otro/CLAUDE.md"
ln -s "$TMP/otro/CLAUDE.md" "$CASA/.claude/CLAUDE.md"
antes=$(estado_total)
instalar --non-interactive
if [ "$RC" -eq 2 ] && [ "$antes" = "$(estado_total)" ] && grep -q "$TMP/otro/CLAUDE.md" "$TMP/out" "$TMP/err"; then
  ok install_refuses_foreign_symlink
else ko "install_refuses_foreign_symlink (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_adopt_copies_into_repo_then_links: skill que el repo no tiene.
nuevo_entorno
mkdir -p "$CASA/.claude/skills/mia"
echo "skill propia" > "$CASA/.claude/skills/mia/SKILL.md"
instalar --adopt --non-interactive
r=$(respaldos)
bien=1
[ "$RC" -eq 0 ] || { bien=0; echo "  rc=$RC"; cat "$TMP/err"; }
[ "$(cat "$CLON/skills/mia/SKILL.md" 2>/dev/null)" = "skill propia" ] || { bien=0; echo "  no se copio al repo"; }
es_enlace_a "$CASA/.claude/skills/mia" "$CLON/skills/mia" || { bien=0; echo "  enlace"; }
[ "$(cat "$r/.claude/skills/mia/SKILL.md" 2>/dev/null)" = "skill propia" ] || { bien=0; echo "  respaldo"; }
grep -q "^adopt	$CLON/skills/mia	" "$CASA/.claude/.p4-manifest" || { bien=0; echo "  manifiesto adopt"; }
[ "$bien" -eq 1 ] && ok install_adopt_copies_into_repo_then_links || ko install_adopt_copies_into_repo_then_links
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_adopt_identical_file_links
nuevo_entorno
mkdir -p "$CASA/.claude"
cp "$CLON/CLAUDE.md" "$CASA/.claude/CLAUDE.md"
repo_antes=$(huella "$CLON")
instalar --adopt --non-interactive
r=$(respaldos)
if [ "$RC" -eq 0 ] && es_enlace_a "$CASA/.claude/CLAUDE.md" "$CLON/CLAUDE.md" \
  && cmp -s "$r/.claude/CLAUDE.md" "$CLON/CLAUDE.md" \
  && [ "$repo_antes" = "$(huella "$CLON" | grep -v '^F \./machine\.env ')" ]; then
  ok install_adopt_identical_file_links
else ko "install_adopt_identical_file_links (rc=$RC)"; cat "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_adopt_differing_file_exit_2: el repo ya lo tiene y difiere; nada cambia.
nuevo_entorno
mkdir -p "$CASA/.claude"
echo "version local distinta" > "$CASA/.claude/CLAUDE.md"
antes=$(estado_total)
instalar --adopt --non-interactive
if [ "$RC" -eq 2 ] && [ "$antes" = "$(estado_total)" ] && grep -q 'version local distinta' "$TMP/out" "$TMP/err"; then
  ok install_adopt_differing_file_exit_2
else ko "install_adopt_differing_file_exit_2 (rc=$RC)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_backs_up_modified_settings
nuevo_entorno
instalar --non-interactive
cp "$CASA/.claude/settings.json" "$TMP/generado.json"
node -e 'const f=process.argv[1],fs=require("fs");const s=JSON.parse(fs.readFileSync(f,"utf8"));s.aMano=true;fs.writeFileSync(f,JSON.stringify(s));' "$CASA/.claude/settings.json"
cp "$CASA/.claude/settings.json" "$TMP/modificado.json"
instalar --non-interactive
rc2=$RC
r=$(respaldos)
bak=$(ls "$r"/settings.json.p4-bak-* 2>/dev/null)
instalar --non-interactive
if [ "$rc2" -eq 0 ] && cmp -s "$CASA/.claude/settings.json" "$TMP/generado.json" \
  && [ ! -L "$CASA/.claude/settings.json" ] && [ -n "$bak" ] && cmp -s "$bak" "$TMP/modificado.json" \
  && [ "$(respaldos | grep -c .)" -eq 1 ]; then
  ok install_backs_up_modified_settings
else ko "install_backs_up_modified_settings (rc=$rc2, bak=$bak)"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_dry_run_changes_nothing: settings previo distinto y sin machine.env.
nuevo_entorno
mkdir -p "$CASA/.claude"
echo '{"x":1}' > "$CASA/.claude/settings.json"
antes=$(estado_total)
instalar --dry-run --non-interactive
if [ "$RC" -eq 0 ] && [ "$antes" = "$(estado_total)" ] && [ ! -s "$TMP/llamadas.log" ] \
  && grep -q 'CLAUDE.md' "$TMP/out" && grep -q 'settings.json' "$TMP/out"; then
  ok install_dry_run_changes_nothing
else ko "install_dry_run_changes_nothing (rc=$RC)"; cat "$TMP/out" "$TMP/err" | head -20; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_resumes_after_interrupt: P4_FAIL_AFTER (solo pruebas) corta tras un paso.
nuevo_entorno
mkdir -p "$CASA/.claude"
echo '{"x":1}' > "$CASA/.claude/settings.json"
instalar --non-interactive
rc_limpio=$RC
limpio=$(huella "$CASA"; echo ==; cat "$TMP/gitconfig" | sed "s|$TMP|TMP|g")
rm -rf "$TMP"
nuevo_entorno
mkdir -p "$CASA/.claude"
echo '{"x":1}' > "$CASA/.claude/settings.json"
P4_FAIL_AFTER=enlaces; export P4_FAIL_AFTER
instalar --non-interactive; rc_a=$RC
P4_FAIL_AFTER=settings
instalar --non-interactive; rc_b=$RC
unset P4_FAIL_AFTER
instalar --non-interactive; rc_c=$RC
final=$(huella "$CASA"; echo ==; cat "$TMP/gitconfig" | sed "s|$TMP|TMP|g")
r=$(respaldos)
if [ "$rc_limpio" -eq 0 ] && [ "$rc_a" -ne 0 ] && [ "$rc_b" -ne 0 ] && [ "$rc_c" -eq 0 ] \
  && [ "$limpio" = "$final" ] && [ "$(printf '%s\n' "$r" | grep -c .)" -eq 1 ] \
  && [ "$(cat "$r"/settings.json.p4-bak-* 2>/dev/null)" = '{"x":1}' ]; then
  ok install_resumes_after_interrupt
else
  ko "install_resumes_after_interrupt (rc $rc_limpio $rc_a $rc_b $rc_c)"
  printf '%s\n' "$limpio" > "$TMP/l"; printf '%s\n' "$final" | diff "$TMP/l" - | head -20
fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_missing_node_exit_3: PATH con lo basico pero sin node.
nuevo_entorno
mkdir -p "$TMP/sinnode"
for b in sh dash git uname dirname basename cat mkdir ln cp mv rm cmp diff date mktemp chmod \
  grep sed find sort printf readlink tr env ls cut head wc touch; do
  p=$(command -v "$b" 2>/dev/null) && case $p in /*) ln -s "$p" "$TMP/sinnode/$b" ;; esac
done
env HOME="$CASA" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/sinnode" \
  "$TMP/sinnode/$TEST_SH" "$CLON/install.sh" --non-interactive </dev/null >"$TMP/out" 2>"$TMP/err"
RC=$?
if [ "$RC" -eq 3 ] && [ ! -e "$CASA/.claude" ] && grep -q 'node' "$TMP/err"; then ok install_missing_node_exit_3
else ko "install_missing_node_exit_3 (rc=$RC)"; cat "$TMP/err"; fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
# install_respects_foreign_git_hooks: hooksPath ya fijado y contenido ajeno en hooks/.
nuevo_entorno
GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 git config --global core.hooksPath /otra/ruta
mkdir -p "$CASA/.config/git/hooks"
echo '#!/bin/sh' > "$CASA/.config/git/hooks/pre-commit"
instalar --non-interactive
if [ "$RC" -eq 0 ] && [ ! -L "$CASA/.config/git/hooks/pre-commit" ] && [ ! -e "$CASA/.config/git/hooks/lib.sh" ] \
  && [ "$(GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 git config --global --get core.hooksPath)" = /otra/ruta ] \
  && grep -qi 'aviso' "$TMP/err"; then
  ok install_respects_foreign_git_hooks
else ko "install_respects_foreign_git_hooks (rc=$RC)"; fi
rm -rf "$TMP"

exit $FAIL
