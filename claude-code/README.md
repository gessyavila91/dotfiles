# claude-code

Configuración portable de Claude Code (reglas, ajustes, skills, hooks propios) versionada en este repositorio. Es la fuente de verdad; `~/.claude/` solo contiene enlaces o copias generadas desde aquí.

Contenido actual:

- `INVENTARIO.md`: qué hay hoy en `~/.claude/` y `~/.config/git/hooks/`, qué es propio y qué viene de fuera.
- `tools/lint.sh`: comprueba que el árbol no tenga JSON inválido, rutas literales de usuario ni cadenas con forma de secreto. Requiere `node` 18 o superior.
- `tests/test-lint.sh`: pruebas de `lint.sh`.
- `mcp.json`, `lib/mcp-register.sh`, `lib/mcp-helper.mjs`: lista de MCP de usuario y su registro. `mcp_register <mcp.json> <machine.env> <os>` (cargar con `.` y definir `MCP_REGISTER_DIR` con la ruta de `lib/`) llama a `claude mcp add-json --scope user <nombre> '<json>'`, sintaxis verificada con `claude mcp add-json --help`: el JSON va como un solo argumento, sin escapado extra en sh (el escapado en PowerShell sigue sin verificar). Es idempotente: pregunta con `claude mcp get <nombre>` y solo registra si falta o difiere (tipo, command, args o URL).
- Rutas con `{{HOME}}` se resuelven al registrar. `phpstorm` y `pycharm` (`when: "ide"`, solo con `IDE_MCP=yes`) llevan `{{PHPSTORM_URL}}` y `{{PYCHARM_URL}}`, que se rellenan con las claves opcionales del mismo nombre de `machine.env` (el puerto lo fija el IDE y cambia por equipo); si falta una, ese MCP se omite con un aviso. `mcp.json` no lleva `env` ni `headers`.
- `versions.lock`: versiones fijadas (`clave=valor`) de `codebase-memory-mcp` y de los plugins habilitados (`plugin.<id>=<versión>`).
- `update-versions.sh`: reescribe `versions.lock` desde lo instalado (ver «Versiones fijadas»). `tests/test-update-versions.sh`: sus pruebas.
- `tests/test-mcp.sh`: pruebas del registro con un `claude` falso.

## Instalar (macOS y Linux)

`sh claude-code/install.sh [--dry-run] [--adopt] [--non-interactive]`

- Enlaza en `~/.claude/` `CLAUDE.md`, cada carpeta de `skills/`, cada archivo de `hooks/` y `themes/dracula.json`; enlaza los 14 hooks de `git-hooks/NAMES` (a `dispatch`) y `lib.sh` en `~/.config/git/hooks/`, solo si esa carpeta no tiene contenido ajeno, y fija `core.hooksPath` solo si no estaba fijado (si no, avisa). Usa `ln -s`; no usa `stow` (decisión por simplicidad).
- Los enlaces apuntan al clon desde el que se ejecuta. Un worktree temporal no debe ser la fuente a largo plazo: instale desde el clon definitivo (`~/.config`).
- `settings.json` no es un enlace: se genera con `lib/merge-settings.mjs` (`--os` según `uname`). Si difiere del actual, el anterior se guarda como `settings.json.p4-bak-<fecha>` en el respaldo; si es igual, no se toca.
- `machine.env` (en `claude-code/`, ignorado por `claude-code/.gitignore`): si falta, lo pregunta; con `--non-interactive` lo crea desde `machine.env.example` con `IDE_MCP=no`.
- Respaldo: `~/Respaldos/p4-AAAAMMDD-HHMMSS-XXXXXX` (permisos 700), solo si algo existente va a cambiar. El instalador nunca lo borra.
- Un destino que ya existe y no es un enlace a este clon (archivo, carpeta o enlace a otro sitio) detiene la instalación con código 2 y muestra la diferencia. `--adopt`: si el repo no tiene ese elemento, lo copia al repo (hay que commitearlo después), lo respalda y pone el enlace; si el repo lo tiene igual, respalda y enlaza; si el repo lo tiene distinto, muestra la diferencia y sale con 2 sin tocar nada. No se adopta lo que es o contiene enlaces simbólicos, ni lo que figura en `adopt-ignore` (rutas relativas a `~/.claude`, una por línea, comparación literal; hoy `skills/synced`, la caché de la app) cuando el repo no lo tiene: se informa `ignorado: <ruta> (adopt-ignore)` y no se toca. Si `~/.claude`, sus carpetas `skills/`, `hooks/`, `themes/` o `~/.config/git/hooks` son enlaces simbólicos (p. ej. hechos con `stow`) o resuelven dentro del clon o fuera de `HOME`, sale con 2 aunque se use `--adopt`: hay que resolverlo a mano.
- Códigos de salida: 0 bien, 2 conflicto, 3 falta `node` o `git` (o el sistema no es macOS, Linux ni Windows con Git Bash), 1 otro fallo. Si falta `claude` o `docker`, solo avisa.
- `--copy` (o `P4_COPY=1` en el entorno; en Windows siempre) instala en modo copia: ver la sección de Windows. Una instalación es de enlaces o de copias; para cambiar de modo hay que desinstalar antes (si no, sale con 2).
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

## Versiones fijadas

`versions.lock` fija (`clave=valor`, ordenado por clave) la versión de `codebase-memory-mcp` y la de cada plugin habilitado (`plugin.<id>@<marketplace>=<versión>`). Nada lo cambia solo: solo sube cuando usted lo pide.

- Subir las versiones: `sh claude-code/update-versions.sh`. Lee lo instalado con las mismas funciones que `doctor` (`lib/common.sh`), incluye solo los plugins con `enabledPlugins` en `true` en `~/.claude/settings.json` y reescribe `versions.lock` de forma determinista (claves ordenadas, salto de línea final, vía archivo temporal). Luego revise la diferencia con `git diff claude-code/versions.lock` y haga commit.
- `--dry-run` muestra la diferencia (`-` actual, `+` nueva) y no escribe nada. `--check` sale con 0 si el lock ya coincide con lo instalado y con 1 si no; tampoco escribe.
- Si una fuente falta (binario, `installed_plugins.json`, `settings.json`, o un plugin habilitado que no está instalado) avisa y deja esa clave como estaba: nunca la borra en silencio. Un plugin deshabilitado sí sale del lock. Sin `node` sale con 3. Solo toca `versions.lock`.
- `doctor` compara cada equipo con el lock y lista como `diferencia:` las versiones distintas, así que un equipo con otra versión se ve de inmediato; tras `update-versions.sh` en el mismo equipo no debe haber diferencias de versión.
- Windows: no hace falta un `.ps1` nuevo; en Git Bash se ejecuta con `sh claude-code/update-versions.sh`, igual que en macOS y Linux.
- Pruebas: `sh claude-code/tests/test-update-versions.sh` (también con `TEST_SH=dash`).

## Windows (modo copia)

Claude Code en Windows ya requiere Git Bash, así que se usan los mismos scripts POSIX ejecutados con Git Bash. `install.ps1`, `uninstall.ps1` y `doctor.ps1` son envoltorios mínimos: buscan `bash.exe` de Git for Windows (junto a `git.exe`, o en `C:\Program Files\Git\bin\bash.exe`), fijan `P4_COPY=1` y ejecutan el `.sh` del mismo nombre traduciendo `-DryRun`, `-Adopt` y `-NonInteractive` a `--dry-run`, `--adopt` y `--non-interactive`. Devuelven el código de salida del script. **Los envoltorios `.ps1` no se han ejecutado nunca** (no había PowerShell donde se escribieron): hay que comprobarlos en la laptop (ver abajo).

- Requisitos: Git for Windows (con Git Bash), Node.js y la CLI `claude` en el `PATH`. Solo se soporta Git Bash (`uname` `MINGW…`/`MSYS…`); Cygwin no.
- ExecutionPolicy: con la política por defecto (`Restricted`) o una GPO de la empresa, `.\install.ps1` se bloquea antes de ejecutarse. Ejecutarlo con `powershell -ExecutionPolicy Bypass -File <ruta>\claude-code\install.ps1 -NonInteractive` (igual para `uninstall.ps1` y `doctor.ps1`), o, si la GPO lo permite, una vez `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- Clonar el repo en `%USERPROFILE%\.config` y ejecutar, desde PowerShell, `powershell -ExecutionPolicy Bypass -File .\.config\claude-code\install.ps1 -NonInteractive` (o, desde Git Bash, `sh ~/.config/claude-code/install.sh`, que en Windows usa copias aunque no se pase `--copy`).
- Semántica de copia: en vez de enlaces, se copian `CLAUDE.md`, cada skill, cada hook, el tema y los hooks de git (los 14 nombres de `git-hooks/NAMES` son copias de `dispatch`, junto a `lib.sh`), con `cp -Rp` a una carpeta temporal hermana y luego `mv`. El manifiesto anota cada copia (`copia`); es lo que la hace «nuestra». **Tras cambiar algo en el repo hay que volver a ejecutar el instalador**: una copia nuestra que difiere del repo se actualiza y la anterior se guarda en `<respaldo>/p4-copias-previas/` (no se restaura al desinstalar); el instalador avisa (`aviso:`) con esa ruta, por si la copia tenía ediciones propias. Un destino que no es nuestro sigue el mismo camino que con enlaces (conflicto con 2, o `--adopt`).
- `uninstall` quita solo las copias idénticas al repo; una copia con cambios a mano (o desfasada porque el repo cambió sin reinstalar) se conserva y se avisa, y lo que el respaldo tenga en esa ruta se queda en el respaldo. `doctor` compara cada copia con el repo y señala las que faltan, difieren o ya no tienen origen.
- En Git Bash `uname` da `MINGW…`/`MSYS…`: el sistema se detecta como `windows` (plantilla `settings.windows.json`, `NODE=node`).
- `claude-code/.gitattributes` fuerza fin de línea LF en todo `claude-code/` (no en el resto del repo): con `core.autocrlf=true` (lo habitual en Git for Windows) un CRLF rompe los scripts de sh.
- Las pruebas del modo copia se ejecutan en macOS con un `HOME` temporal (`install_copy_mode_*`, `uninstall_copy_mode_*`, `doctor_copy_mode_*`); lo propio de Windows no.

### Comprobaciones en Windows

Pendientes en la laptop, en este orden (nada de esto se ha probado):

0. ExecutionPolicy: `Get-ExecutionPolicy -List`. Si `.\.config\claude-code\doctor.ps1` dice que la ejecución de scripts está deshabilitada, usar `powershell -ExecutionPolicy Bypass -File <ruta>\claude-code\<script>.ps1 …` en todos los pasos siguientes (o `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` si la GPO lo permite) y anotar cuál funcionó.
1. `git --version`, `node --version` y `claude --version` responden en PowerShell; `& 'C:\Program Files\Git\bin\bash.exe' -c 'echo $HOME; uname -s; command -v node'` muestra el `HOME` equivalente a `%USERPROFILE%`, `MINGW64_NT-…` y una ruta a `node`.
2. `.\.config\claude-code\install.ps1 -DryRun -NonInteractive`: dice «modo copia» y lista copias, no enlaces; no escribe nada.
3. `.\.config\claude-code\install.ps1 -NonInteractive` (o con `-Adopt` si ya hay un `~\.claude` usado): sale con 0; `~\.claude\CLAUDE.md`, `skills\`, `hooks\` y `~\.config\git\hooks\` tienen archivos normales; `git config --global core.hooksPath` apunta a `~/.config/git/hooks`; `echo $LASTEXITCODE` coincide con el del script.
4. Repetirlo: no cambia nada. Cambiar una línea de `CLAUDE.md` en el repo y repetirlo: se actualiza y la anterior queda en `~\Respaldos\p4-…\p4-copias-previas`.
5. `.\.config\claude-code\doctor.ps1`: sale con 0 (o solo con diferencias esperables de versiones). Editar `~\.claude\CLAUDE.md` a mano: `doctor` lo señala.
6. `claude mcp list`: aparecen los MCP de `mcp.json` que aplican.
7. Hooks bajo Git Bash: abrir Claude Code y comprobar que se ejecutan `gitflow-guard.sh` y `estado-guard.sh` (p. ej. un `git push` a `main` bloqueado) y que `settings.json` usa rutas que Git Bash entiende (`/c/<perfil>/...`); un `git push` en un repo con los hooks globales pasa por `dispatch`.
8. `node` en el `PATH` de los hooks: el hook de ccdeck (`{{NODE}}` = `node`) no falla.
9. `.\.config\claude-code\uninstall.ps1 -DryRun` y luego `uninstall.ps1`: quita las copias, restaura el respaldo y deja `core.hooksPath` como estaba; repetirlo sale con 1 («nada instalado»).

Reglas del árbol: scripts en POSIX sh, sin rutas absolutas de usuario (usar `~` o `$HOME`), sin secretos, textos en español.

Ejecutar las pruebas: `sh claude-code/tests/test-lint.sh`, `sh claude-code/tests/test-content.sh`, `sh claude-code/tests/test-mcp.sh`, `sh claude-code/tests/test-install.sh` y `sh claude-code/tests/test-uninstall-doctor.sh` (ambas también con `TEST_SH=dash`) y `node --test claude-code/tests/*.test.mjs`.
