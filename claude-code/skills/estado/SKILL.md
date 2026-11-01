---
name: estado
description: Use when the user asks "¿en qué estamos?", "estado", "dónde quedamos" or similar — reports open plans, next task, git state, pending decisions and whether a new feature can start.
---

# estado

Informe de continuidad del repo actual: planes abiertos, siguiente tarea,
estado de git, decisiones pendientes y si se puede empezar una feature nueva.

## Pasos

1. Ejecuta desde el `cwd` de la sesión:
   `sh ~/.claude/skills/estado/estado.sh`
2. Presenta la salida tal cual. No releas los planes ni resumas por tu cuenta:
   el script ya leyó lo necesario.
3. Si `Sin estado` es mayor que 0, ofrece clasificar esos planes:
   - propón una lista (por ejemplo, PR mergeado -> `ejecutado`);
   - escribe en los planes solo lo que la usuaria confirme.
4. No toques repos en pausa (Godot, U6) salvo petición expresa.

## Notas

- El informe usa el repo local; solo la lista de PR abiertos puede llamar a `gh pr list` (si hay `gh` y un remoto).
- Fuera de un repo git, el script lo indica y no hay más que hacer.
