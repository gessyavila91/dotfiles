# Inventario de la configuración de Claude Code

Estado observado el 2026-10-31 en el Mac personal. Solo lectura: nada de lo listado se ha movido. Las rutas usan `~`. "Windows" indica si la pieza funciona sin cambios allí.

Leyenda de origen: propia (escrita por la usuaria), plugin (la trae un plugin de `~/.claude/plugins`), externa (instalación de terceros o gestor de paquetes).

## ~/.claude/skills/

| Entrada | Origen | Enlace | Windows | Notas |
| --- | --- | --- | --- | --- |
| `desatendido/` | propia | no | parcial | `SKILL.md` portable; `cola.sh` es POSIX sh y necesita sh en Windows (Git Bash) |
| `estado/` | propia | no | parcial | `SKILL.md` portable; `estado.sh` y `estado-lib.sh` son POSIX sh (Git Bash) |
| `caveman/` | externa | no | si | solo Markdown (`SKILL.md`, `README.md`); no consta en ningún plugin instalado |
| `codebase-memory/` | externa | no | si | solo `SKILL.md`; no consta en ningún plugin instalado |
| `find-skills/` | externa | no | si | solo `SKILL.md`; no consta en ningún plugin instalado |
| `frontend-design` | externa | si, a `~/.agents/skills/frontend-design` (ruta relativa) | no | el enlace simbólico exige modo desarrollador en Windows; se debe copiar el contenido o reinstalar |
| `llm-council` | externa | si, a `~/.agents/skills/llm-council` (ruta relativa) | no | igual que el anterior |
| `peon-ping-config/` | externa (Homebrew peon-ping) | si, `SKILL.md` a Homebrew | no | se reinstala con el paquete; no se copia |
| `peon-ping-log/` | externa (Homebrew peon-ping) | ver peon-ping-config | no | mismo caso |
| `peon-ping-toggle/` | externa (Homebrew peon-ping) | ver peon-ping-config | no | mismo caso |
| `peon-ping-use/` | externa (Homebrew peon-ping) | ver peon-ping-config | no | mismo caso |
| `synced/` | externa (sincronizada por Claude, skills de Anthropic) | no | n/a | caché administrada por la aplicación (`manifest.json`, built-in-browser, docx, pdf, ...); no se versiona |
| `.trash/` | externa | no | n/a | papelera de la aplicación; no se versiona |

Los skills de plugins (superpowers, etc.) viven en `~/.claude/plugins/cache` y no están en `skills/`. Plugins instalados: gitkraken-hooks, laravel-boost, superpowers, notification, clangd-lsp, savvy-progress, filetree.

## ~/.claude/hooks/

| Entrada | Origen | Enlace | Windows | Notas |
| --- | --- | --- | --- | --- |
| `estado-guard.sh`, `estado-lib.sh`, `estado-session.sh` | propia | no | parcial | POSIX sh; requieren sh (Git Bash) |
| `gitflow-guard.sh`, `gitflow-guard-lib.sh` | propia | no | parcial | POSIX sh; requieren sh (Git Bash) |
| `cbm-code-discovery-gate`, `cbm-session-reminder`, `cbm-subagent-reminder` | externa (codebase-memory-mcp) | no | parcial | scripts que instala esa herramienta; se reinstalan con ella |
| `peon-ping/` | externa (Homebrew peon-ping) | mixto | no | ver abajo |

Dentro de `hooks/peon-ping/`: `peon.sh`, `relay.sh`, `uninstall.sh`, `VERSION`, `completions.*` son enlaces a `/opt/homebrew/opt/peon-ping/libexec/` y `packs` es un enlace a `~/.openpeon/packs`. El resto (`adapters/`, `scripts/`, `mcp/`, `trainer/`, `docs/`) son copias que deja el instalador. `config.json` es configuración de la usuaria; `.state.json`, `.sound.pid`, `.last_update_check` y `.update_available` son estado de ejecución. Decisión: no se copia nada de `peon-ping/`; se reinstala con su paquete, y como máximo se versionaría `config.json`. En Windows peon-ping tiene su propio instalador.

## ~/.claude/agent-dag/

Instalado por ccdeck (herramienta externa, versión 3.51.0 según su archivo de estado); no es de la usuaria. Contenido:

| Entrada | Qué es | Versionar |
| --- | --- | --- |
| `hook.js` | script Node sin dependencias externas (solo módulos integrados: fs, path, http, os, crypto) | no; lo regenera ccdeck |
| `package.json` | solo `{ "type": "commonjs" }` | no |
| `settings.before-skill-hook.json` | copia de seguridad de ajustes | no |
| `<pid>.json` (por ejemplo `10736.json`) | estado de ejecución con puerto y token | nunca (contiene un token) |
| `browser-watch/` | datos temporales | no |

No tiene `node_modules`. `settings.json` lo invoca con la ruta absoluta de `hook.js` y del ejecutable de node; esa ruta habrá que sustituir al generar los ajustes portables. Windows: funcionaría con Node instalado, pero lo gestiona ccdeck.

## ~/.config/git/hooks/

| Entrada | Origen | Enlace | Windows | Notas |
| --- | --- | --- | --- | --- |
| `dispatch` | propia | no | parcial | POSIX sh; ejecutor común |
| `lib.sh` | propia | no | parcial | biblioteca de `dispatch` |
| 14 hooks de git: `applypatch-msg`, `commit-msg`, `post-applypatch`, `post-checkout`, `post-commit`, `post-merge`, `post-rewrite`, `pre-applypatch`, `pre-auto-gc`, `pre-commit`, `pre-merge-commit`, `pre-push`, `pre-rebase`, `prepare-commit-msg` | propia | si, todos a `dispatch` (relativo) | no | en Windows se materializan como copias de `dispatch` |

## Hallazgos para las tareas siguientes

- `settings.json` contiene rutas absolutas del directorio personal en los hooks de ccdeck: hay que parametrizarlas.
- Nada de lo externo se versiona; solo lo propio: skills `desatendido` y `estado`, hooks `estado-*` y `gitflow-guard*`, y `git/hooks`.
- `agent-dag/` contiene un token de ejecución: debe quedar fuera del repositorio.

## Plantillas de settings (tarea 3)

- `settings.base.json` sale del `settings.json` de la Mac con el directorio personal cambiado por `{{HOME}}`. Las capas `settings.macos.json`, `settings.linux.json` y `settings.windows.json` quedan en `{}`: los comandos de los hooks son iguales en todos los sistemas por ahora.
- Valores propios de esta Mac que siguen en la base y hay que revisar: la ruta `/usr/local/bin/node` y `/usr/bin/notifyutil` en los hooks, y la frase de `autoMode.environment` con el directorio de trabajo de confianza (ahora con `{{HOME}}`). Las listas se reemplazan enteras entre capas, por eso no se pueden separar sin duplicar el bloque `hooks`.
- Windows: el prefijo para invocar los scripts de los hooks sería `bash` de Git Bash; se confirma en la tarea 9.
