# claude-code

Configuración portable de Claude Code (reglas, ajustes, skills, hooks propios) versionada en este repositorio. Es la fuente de verdad; `~/.claude/` solo contiene enlaces o copias generadas desde aquí.

Contenido actual:

- `INVENTARIO.md`: qué hay hoy en `~/.claude/` y `~/.config/git/hooks/`, qué es propio y qué viene de fuera.
- `tools/lint.sh`: comprueba que el árbol no tenga JSON inválido, rutas literales de usuario ni cadenas con forma de secreto. Requiere `node` 18 o superior.
- `tests/test-lint.sh`: pruebas de `lint.sh`.

Reglas del árbol: scripts en POSIX sh, sin rutas absolutas de usuario (usar `~` o `$HOME`), sin secretos, textos en español.

Ejecutar las pruebas: `sh claude-code/tests/test-lint.sh`.
