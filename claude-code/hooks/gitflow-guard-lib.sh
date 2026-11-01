#!/bin/sh
# Biblioteca común de gitflow-guard. Solo definiciones (sin efectos al cargarla).

GFG_DEFAULT_PROTECTED="main master develop dev"
GFG_HOOK_NAMES="applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite pre-auto-gc"

# gfg_protected_list <repo_dir>: una rama protegida por línea.
gfg_protected_list() {
  for _b in $GFG_DEFAULT_PROTECTED; do
    printf '%s\n' "$_b"
  done
  git -C "$1" config --get-all gitflow-guard.protected 2>/dev/null
  return 0
}

# gfg_is_protected <repo_dir> <branch>: exit 0 si la rama está protegida.
gfg_is_protected() {
  gfg_protected_list "$1" | grep -qxF -- "$2"
}

# gfg_is_exempt <repo_dir>: exit 0 si gitflow-guard.exempt es true.
gfg_is_exempt() {
  [ "$(git -C "$1" config --bool gitflow-guard.exempt 2>/dev/null)" = "true" ]
}
