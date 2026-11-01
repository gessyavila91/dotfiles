# claude-code

Configuración portable de Claude Code (reglas, ajustes, skills, hooks propios) versionada en este repositorio. Es la fuente de verdad; `~/.claude/` solo contiene enlaces o copias generadas desde aquí.

Contenido actual:

- `INVENTARIO.md`: qué hay hoy en `~/.claude/` y `~/.config/git/hooks/`, qué es propio y qué viene de fuera.
- `tools/lint.sh`: comprueba que el árbol no tenga JSON inválido, rutas literales de usuario ni cadenas con forma de secreto. Requiere `node` 18 o superior.
- `tests/test-lint.sh`: pruebas de `lint.sh`.
- `mcp.json`, `lib/mcp-register.sh`, `lib/mcp-helper.mjs`: lista de MCP de usuario y su registro. `mcp_register <mcp.json> <machine.env> <os>` (cargar con `.` y definir `MCP_REGISTER_DIR` con la ruta de `lib/`) llama a `claude mcp add-json --scope user <nombre> '<json>'`, sintaxis verificada con `claude mcp add-json --help`: el JSON va como un solo argumento, sin escapado extra en sh (el escapado en PowerShell sigue sin verificar). Es idempotente: pregunta con `claude mcp get <nombre>` y solo registra si falta o difiere (tipo, command, args o URL).
- Rutas con `{{HOME}}` se resuelven al registrar. `phpstorm` y `pycharm` (`when: "ide"`, solo con `IDE_MCP=yes`) llevan `{{PHPSTORM_URL}}` y `{{PYCHARM_URL}}`, que se rellenan con las claves opcionales del mismo nombre de `machine.env` (el puerto lo fija el IDE y cambia por equipo); si falta una, ese MCP se omite con un aviso. `mcp.json` no lleva `env` ni `headers`.
- `versions.lock`: versiones fijadas (`clave=valor`) de `codebase-memory-mcp` y de los plugins habilitados (`plugin.<id>=<versión>`).
- `tests/test-mcp.sh`: pruebas del registro con un `claude` falso.

## Instalar (macOS y Linux)

`sh claude-code/install.sh [--dry-run] [--adopt] [--non-interactive]`

- Enlaza en `~/.claude/` `CLAUDE.md`, cada carpeta de `skills/`, cada archivo de `hooks/` y `themes/dracula.json`; enlaza los 14 hooks de `git-hooks/NAMES` (a `dispatch`) y `lib.sh` en `~/.config/git/hooks/`, solo si esa carpeta no tiene contenido ajeno, y fija `core.hooksPath` solo si no estaba fijado (si no, avisa). Usa `ln -s`; no usa `stow` (decisión por simplicidad).
- Los enlaces apuntan al clon desde el que se ejecuta. Un worktree temporal no debe ser la fuente a largo plazo: instale desde el clon definitivo (`~/.config`).
- `settings.json` no es un enlace: se genera con `lib/merge-settings.mjs` (`--os` según `uname`). Si difiere del actual, el anterior se guarda como `settings.json.p4-bak-<fecha>` en el respaldo; si es igual, no se toca.
- `machine.env` (en `claude-code/`, ignorado por `claude-code/.gitignore`): si falta, lo pregunta; con `--non-interactive` lo crea desde `machine.env.example` con `IDE_MCP=no`.
- Respaldo: `~/Respaldos/p4-AAAAMMDD-HHMMSS-XXXXXX` (permisos 700), solo si algo existente va a cambiar. El instalador nunca lo borra.
- Un destino que ya existe y no es un enlace a este clon (archivo, carpeta o enlace a otro sitio) detiene la instalación con código 2 y muestra la diferencia. `--adopt`: si el repo no tiene ese elemento, lo copia al repo (hay que commitearlo después), lo respalda y pone el enlace; si el repo lo tiene igual, respalda y enlaza; si el repo lo tiene distinto, muestra la diferencia y sale con 2 sin tocar nada. No se adopta lo que es o contiene enlaces simbólicos. Si `~/.claude`, sus carpetas `skills/`, `hooks/`, `themes/` o `~/.config/git/hooks` son enlaces simbólicos (p. ej. hechos con `stow`) o resuelven dentro del clon o fuera de `HOME`, sale con 2 aunque se use `--adopt`: hay que resolverlo a mano.
- Códigos de salida: 0 bien, 2 conflicto, 3 falta `node` o `git` (o el sistema no es macOS ni Linux), 1 otro fallo. Si falta `claude` o `docker`, solo avisa.
- Al final registra los MCP con `mcp_register`. `--dry-run` muestra lo que haría sin escribir nada.
- Manifiesto: `~/.claude/.p4-manifest` (formato en `lib/common.sh`); lo leerán `uninstall` y `doctor`.
- Repetir la instalación es seguro: cada paso es idempotente. `P4_FAIL_AFTER=<paso>` fuerza un fallo tras ese paso y existe solo para las pruebas.

## Desinstalar y comprobar

- `sh claude-code/uninstall.sh [--dry-run]` deshace la instalación leyendo `~/.claude/.p4-manifest`: quita solo los enlaces que siguen apuntando a este clon, restaura `settings.json` desde la copia del respaldo (sin copia, lo borra solo si es idéntico al generado; si no, lo deja y avisa), copia de vuelta lo que se movió al respaldo, quita `core.hooksPath` solo si lo fijó el instalador y conserva su valor, y quita las carpetas que creó si quedan vacías. Lo adoptado al repo no se borra del repo, el respaldo no se borra nunca, lo desconocido en `~/.claude` no se toca, y el manifiesto se quita al final.
- Antes de cambiar nada comprueba todo: sale con 2 sin tocar nada si el manifiesto es incoherente (línea desconocida, enlace de otro clon, ruta fuera de `HOME`, respaldo ausente, destino de restauración ocupado). Sale con 1 y "nada instalado" si no hay manifiesto, así que repetirlo no hace nada. No anula el registro de los MCP: viven en `~/.claude.json`, que no se edita a mano; al terminar imprime los `claude mcp remove --scope user <nombre>` que hay que ejecutar.
- `sh claude-code/doctor.sh` solo lee y sale con 0 si el equipo coincide con el repo, o con 1 listando cada `diferencia:`: enlaces que faltan, rotos, ajenos o convertidos en copia, `core.hooksPath`, `settings.json` distinto del regenerado con `merge-settings.mjs`, versiones de `versions.lock` y MCP de `mcp.json` ausentes en `claude mcp list`.
- Versiones: `codebase-memory-mcp` se lee de `~/.local/bin/codebase-memory-mcp --version` (primer `X.Y.Z` de la salida) y los plugins de `~/.claude/plugins/installed_plugins.json` (`plugins.<id>[].version`). Si la fuente no existe (binario, archivo o `claude`) es un aviso en stderr, no una diferencia; un plugin ausente de un archivo que sí existe sí lo es.
- Con varias instalaciones, la copia «última» de `settings.json` en el respaldo es la de la última instalación que respaldó algo, no necesariamente el original previo a la primera. Si `settings.json` ya era idéntico al generado al instalar, el manifiesto lo anota como `preexistente` y `uninstall` lo conserva. Dos respaldos con la misma ruta y contenido distinto hacen salir con 2 sin tocar nada.
- Pruebas: `sh claude-code/tests/test-uninstall-doctor.sh` (también con `TEST_SH=dash`).

Reglas del árbol: scripts en POSIX sh, sin rutas absolutas de usuario (usar `~` o `$HOME`), sin secretos, textos en español.

Ejecutar las pruebas: `sh claude-code/tests/test-lint.sh`, `sh claude-code/tests/test-mcp.sh`, `sh claude-code/tests/test-install.sh` (también con `TEST_SH=dash`) y `node --test claude-code/tests/*.test.mjs`.
