#!/bin/sh
# Pruebas del contenido portable de claude-code/.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CLAUDE=${CLAUDE_HOME:-$HOME/.claude}
GITHOOKS=${GITHOOKS_HOME:-$HOME/.config/git/hooks}
AGENTS=${AGENTS_HOME:-$HOME/.agents/skills}
FAIL=0

# comparar <copia> <origen>
comparar() {
  # Unica diferencia permitida: el origen puede traer el home literal; la copia usa $HOME.
  if [ -f "$2" ] && grep -qF "$HOME/" "$2"; then
    _t=$(mktemp)
    sed "s|$HOME/|\$HOME/|g" "$2" > "$_t"
    chmod --reference="$2" "$_t" 2>/dev/null || { [ -x "$2" ] && chmod +x "$_t"; }
    set -- "$1" "$_t" "$2"
  fi
  if [ ! -e "$2" ]; then
    echo "AVISO origen ausente, se omite: $2"
    return
  fi
  if [ ! -e "$1" ]; then
    echo "FALLA falta copia: $1"; FAIL=1; return
  fi
  if ! cmp -s "$1" "$2"; then
    echo "FALLA difiere: $1"; FAIL=1
  fi
  if [ -x "${3:-$2}" ] && [ ! -x "$1" ]; then
    echo "FALLA sin bit ejecutable: $1"; FAIL=1
  fi
}

# content_matches_real_claude
comparar "$ROOT/CLAUDE.md" "$CLAUDE/CLAUDE.md"
comparar "$ROOT/themes/dracula.json" "$CLAUDE/themes/dracula.json"
for f in SKILL.md cola.sh; do comparar "$ROOT/skills/desatendido/$f" "$CLAUDE/skills/desatendido/$f"; done
for f in SKILL.md estado.sh estado-lib.sh; do comparar "$ROOT/skills/estado/$f" "$CLAUDE/skills/estado/$f"; done
for f in SKILL.md README.md; do comparar "$ROOT/skills/caveman/$f" "$CLAUDE/skills/caveman/$f"; done
comparar "$ROOT/skills/codebase-memory/SKILL.md" "$CLAUDE/skills/codebase-memory/SKILL.md"
comparar "$ROOT/skills/find-skills/SKILL.md" "$CLAUDE/skills/find-skills/SKILL.md"
for f in SKILL.md LICENSE.txt; do comparar "$ROOT/skills/frontend-design/$f" "$AGENTS/frontend-design/$f"; done
for f in SKILL.md README.md; do comparar "$ROOT/skills/llm-council/$f" "$AGENTS/llm-council/$f"; done
for f in cbm-code-discovery-gate cbm-session-reminder cbm-subagent-reminder estado-guard.sh estado-lib.sh estado-session.sh gitflow-guard.sh gitflow-guard-lib.sh; do
  comparar "$ROOT/hooks/$f" "$CLAUDE/hooks/$f"
done
comparar "$ROOT/git-hooks/dispatch" "$GITHOOKS/dispatch"
comparar "$ROOT/git-hooks/lib.sh" "$GITHOOKS/lib.sh"

# NAMES: los 14 hooks que hoy son enlaces a dispatch
if [ -d "$GITHOOKS" ]; then
  for l in "$GITHOOKS"/*; do
    [ -L "$l" ] && basename "$l"
  done | LC_ALL=C sort > "${TMPDIR:-/tmp}/names.real.$$"
  LC_ALL=C sort "$ROOT/git-hooks/NAMES" 2>/dev/null | diff - "${TMPDIR:-/tmp}/names.real.$$" >/dev/null \
    || { echo "FALLA git-hooks/NAMES no coincide con los enlaces reales"; FAIL=1; }
  rm -f "${TMPDIR:-/tmp}/names.real.$$"
fi
[ "$(grep -c . "$ROOT/git-hooks/NAMES" 2>/dev/null)" = 14 ] || { echo "FALLA NAMES no tiene 14 nombres"; FAIL=1; }

# nunca copiar estado ni tokens de agent-dag
if [ -e "$ROOT/agent-dag" ]; then echo "FALLA agent-dag no debe versionarse"; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "ok   content_matches_real_claude"

# no_symlinks_inside_repo_content
L=$(find "$ROOT" -type l)
if [ -n "$L" ]; then echo "FALLA no_symlinks_inside_repo_content"; echo "$L"; FAIL=1
else echo "ok   no_symlinks_inside_repo_content"; fi

# lint_clean
if sh "$ROOT/tools/lint.sh" "$ROOT" >/dev/null 2>&1; then echo "ok   lint_clean"
else echo "FALLA lint_clean"; sh "$ROOT/tools/lint.sh" "$ROOT" 2>&1 | head -20; FAIL=1; fi

exit $FAIL
