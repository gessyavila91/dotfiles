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

Reglas del árbol: scripts en POSIX sh, sin rutas absolutas de usuario (usar `~` o `$HOME`), sin secretos, textos en español.

Ejecutar las pruebas: `sh claude-code/tests/test-lint.sh`, `sh claude-code/tests/test-mcp.sh` y `node --test claude-code/tests/*.test.mjs`.
