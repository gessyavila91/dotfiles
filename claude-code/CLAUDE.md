# Global rules (all machines, all repos)

A project's own CLAUDE.md overrides anything here.

## Communication
- Reply in the user's language. Write docs, comments and commit descriptions in the language the project uses (check its CLAUDE.md, then its history).
- Say plainly what was done, what was skipped and what failed. No success claims without having run the check.
- For any work with 3 or more steps, create a task list with the task tools at the start and mark each task done as soon as it finishes, so progress is visible in the terminal. When a plan file exists, the task list mirrors it; the plan is the source of truth.

## Safety
- Never delete, move or overwrite existing work without a backup and explicit approval.
- Never commit secrets. `~/.claude.json`, `.env` files and MCP `env`/`headers` values stay out of every repo.
- Ask before anything hard to reverse or outward-facing: pushing (except your own `feature/*`), opening non-draft PRs (never approve or merge them), deleting branches or worktrees, changing repo settings.
- In every repo: never use `--no-verify`, and never `push --force` to shared branches (`--force-with-lease` on your own branch only if asked).

## Plans and progress
- Every plan in docs/superpowers/plans/ carries a status line under its title: `> Estado: pendiente | en ejecución (desde AAAA-MM-DD) | ejecutado AAAA-MM-DD | pausado — <motivo>`. Set it to `en ejecución` when you start and `ejecutado` when you finish.
- Tick each step `[x]` in the plan file as soon as it is done, in the same commit as the work; the plan is the source of truth, not a scratch ledger. Where the estado hook is installed it blocks commits that skip this. Add `[sin-plan]` to the message only when the commit completes no plan step (unrelated work, or a fix to an already-ticked step).
- When asked "¿en qué estamos?" (or "estado", "dónde quedamos"), use the `estado` skill.
- New plans end with a `## Comprobaciones humanas` section (may be empty) and may contain steps titled `Hito (revisión humana): …` where unattended runs must stop.
- When asked to run plans unattended, or to continue an open unattended queue ("sigue"; see `cola.sh actual`), use the `desatendido` skill: do not ask questions except at its stop points, record your decisions in the delivery note, and finish each plan with the delivery note, a draft PR and a notification. Safety and Git rules still apply; anything they require asking about is a stop point.

## Git: Gitflow
Applies when the repo has a `develop` branch. If it does not, ask before creating `develop`; meanwhile branch `feature/*` from the default branch. Before choosing a base branch, run `git branch --list develop` (and check `origin/develop`); the session's git status snapshot does not list other branches.

Protected branches: main, master, develop, dev, plus any the project declares (`git config gitflow-guard.protected`). In a repo without develop, feature/* goes by PR to the default branch.

Branches:
- `main`: released code only; every merge into it gets a SemVer tag `vX.Y.Z`.
- `develop`: integration branch (GitHub default branch in Gitflow repos).
- `feature/<topic>`: from `develop`, back into `develop` via PR. Lowercase, hyphens.
- `release/X.Y.Z`: from `develop`, into `main` AND `develop`. Stabilization only.
- `hotfix/X.Y.Z`: from `main`, into `main` AND `develop`.

Merging:
- `feature/*` → `develop`: squash.
- `release/*` and `hotfix/*` → `main`, and their back-merges → `develop`: merge commit (`--no-ff`), never squash.

Commits: `<type>: <description>` — Conventional Commits type in English (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`), description in the repo's language.

You may, without asking: create `feature/*` from an up-to-date `develop`, work in a worktree, commit, push your own `feature/*`, open a **draft** PR to `develop`.

Ask first before: marking a PR ready; creating `release/*`, `hotfix/*` or tags (only the user releases); changing the default branch; deleting branches or worktrees, even after merge.

Never: commit or push directly to a protected branch (except in exempt repos); decide cleanup with `git branch --merged` (it lies after squash) — check `gh pr view <branch> --json state` instead. Do not install or use the `git-flow` tool; use plain git. Never approve or merge PRs — the user does, on GitHub.

Environments are not branches: dev ← develop, QA/preprod ← release/*, prod ← main. Long-lived environment branches exist only if the project's CLAUDE.md declares them, and they are protected.

Guards (git pre-push and a Claude hook) enforce this. If one blocks you, do not look for a workaround: explain and propose the PR.

A repo with gitflow-guard.exempt=true is a notes/docs repo: work directly on its default branch there. Never mark or unmark a repo as exempt without asking.

Worktrees: only under `.claude/worktrees/<name>`. Make sure the repo's `.gitignore` covers `.claude/worktrees/` and `.claude/settings.local.json` before relying on it.
