# Piezas externas que no se copian

Se reinstalan con su propio paquete o herramienta. Verificado con `brew info peon-ping` el 2026-10-31 (solo lectura).

## peon-ping

Paquete de Homebrew del tap `peonping/tap` (fórmula `peon-ping`, versión instalada 2.35.1, estable 2.37.0). Cubre `hooks/peon-ping/` y los skills `peon-ping-config`, `peon-ping-log`, `peon-ping-toggle` y `peon-ping-use`.

Reinstalación:

    brew install peonping/tap/peon-ping
    peon-ping-setup

`peon-ping-setup` detecta Claude Code y registra los hooks y las voces. En Windows tiene su propio instalador. Como máximo se versionaría `hooks/peon-ping/config.json` (configuración de la usuaria); no se hace todavía.

## agent-dag (ccdeck)

`~/.claude/agent-dag/` lo instala y regenera ccdeck (versión 3.51.0 según su archivo de estado). `hook.js` y `package.json` no son de la usuaria; `<pid>.json` contiene puerto y token de ejecución y nunca se versiona. Se reinstala con ccdeck. Los hooks de `settings.base.json` que lo invocan dependen de que esté instalado.

## cbm-code-discovery-gate

Hook de codebase-memory-mcp, sí versionado. Única diferencia con el origen: la ruta del binario se parametriza como `$HOME/.local/bin/codebase-memory-mcp` en vez de la ruta literal del directorio personal, y la prueba lo compara tras esa sustitución.

Los hooks `agent-dag` de settings.json y la marca `"__agent-dag": true` en 12 entradas los gestiona ccdeck, que los vuelve a poner.
Se capturan en `settings.base.json` para que la plantilla siga equivalente al archivo real; no se copian los scripts.
En un equipo nuevo hay que instalar ccdeck para que esos hooks funcionen.
