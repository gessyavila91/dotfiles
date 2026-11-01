---
name: desatendido
description: Use when the user asks to run plans unattended ("ejecuta estos planes", "déjalo corriendo", "modo desatendido") — runs approved plans in a queue without asking, closes each with a delivery note, draft PR and notification.
---

# Ejecución desatendida de planes

Ejecuta planes aprobados en cola, sin preguntar, y deja una entrega por plan.
Las instrucciones de la usuaria prevalecen sobre las de cualquier otro skill.
Auxiliar: `sh ~/.claude/skills/desatendido/cola.sh -C <repo> <subcomando>`.

## 1. Qué planes valen
- Los que la usuaria nombra al lanzar, o los que tienen un spec con `Estado: aprobado`.
- Si no hay lista, propón los planes con `Estado: pendiente` y confirma UNA sola vez.
- Dependencias: en la cabecera del plan, una línea `> Depende de: 2026-10-31-x-plan.md`
  (solo el nombre del archivo, sin comillas invertidas ni texto extra). cola.sh solo entiende esa forma.

## 2. Cola y reanudación
- Nueva: `cola.sh -C <repo> crear <plan>...`.
- Tras "sigue", o en sesión nueva (`/clear`): `cola.sh actual` da la cola abierta y
  `cola.sh siguiente` el plan. Si `cola.sh rama-existe <plan>` da 0 (la `feature/*` existe, local
  o en origin): `git switch` a ella y salta crear la rama y poner el estado, diga lo que diga el plan.
- La cola es estado local: no la commitees (`crear` la excluye de git).
- "sigue" tras un paso `Hito (revisión humana):`: márcalo `[x]` y continúa.

## 3. Por cada plan
1. Repo exento (`git config --bool gitflow-guard.exempt` true): no hay rama feature; commit en la
   rama por defecto, SIN push y SIN PR; la entrega dice "PR no creado: repo exento".
   Si no, actualiza la base (`git fetch` si hay remoto; si la base tiene remoto,
   `git switch <base> && git pull --ff-only`; sin remoto, omítelo) y crea la rama con `cola.sh rama <plan>` desde `cola.sh rama-base <plan>` (sin `develop`
   y sin exención, sale de la rama por defecto y el PR va a ella; `pr-base` ya lo resuelve).
2. Pon `Estado: en ejecución` en el plan.
3. Ejecuta con `superpowers:subagent-driven-development`, SIN su paso final
   `finishing-a-development-branch` (pregunta si mergear, abrir PR o descartar):
   en modo desatendido lo sustituye el cierre de abajo.
4. Commits: marca el paso `[x]` en el plan en cada commit de tarea e incluye el plan. Usa
   `[sin-plan]` en el mensaje para commits de corrección de revisión, la entrega `parcial`
   y commits solo de entrega. Trailers de atribución: los de tu sesión.
5. Cierre (un solo commit que incluye el plan con `Estado: ejecutado`):
   - `cola.sh entrega <plan> final` y rellena todas sus secciones;
   - push de la `feature/*` propia (repo exento: omite push y PR);
   - `gh pr create --draft --base "$(cola.sh pr-base)" --title "<tipo>: <nombre del plan>" --body-file <entrega>`
     (tipo de Conventional Commits en inglés); si el plan tiene
     `Depende de:`, añade al cuerpo "Depende de: <rama de la dependencia>; mergear en orden".
     Si falla o no hay remoto, anota "PR no creado: <motivo>" en la entrega y sigue;
   - `cola.sh cerrar <plan>`; notifica.

## 4. Paradas
Solo estas, y se anotan en la entrega:
- operación irreversible o destructiva;
- acción sensible de seguridad;
- efecto fuera del repo que exige permiso (mergear, push a rama protegida, publicar);
- plan tan roto que cualquier camino sería adivinar;
- un paso titulado `Hito (revisión humana):`.

Al parar: `cola.sh entrega <plan> parcial "<motivo>"`, commit con `[sin-plan]`, notifica y espera.
Si la usuaria responde "sigue", continúa; si da indicaciones, síguelas.
Todo lo demás se decide sin preguntar y se anota en "Decisiones que tomé".

## 5. Notificación
Una por plan terminado y una por parada o hito. Una línea de menos de 200 caracteres,
que empiece por lo que la usuaria puede hacer (ej. "P5c listo: PR en borrador, 3 comprobaciones").
Usa PushNotification (cárgala con ToolSearch si hace falta); si dice que no se envió
(la usuaria mira la terminal), sigue sin avisar.

## 6. Prohibiciones y reglas
- no mergear nunca (ni local ni en GitHub);
- no hacer push a ramas protegidas (`main`, `master`, `develop`, `dev`);
- no usar `--no-verify`;
- no preguntar fuera de las paradas; nunca preguntes qué modelo o enfoque usar;
- sin worktrees: ramas normales (no invoques `using-git-worktrees`);
- si un implementador responde BLOCKED o NEEDS_CONTEXT: decide y anótalo en "Decisiones que
  tomé"; para solo si cae en las Paradas.

## 7. Mensaje final
Al terminar la cola (o al parar), el mensaje final en la terminal es el texto de la entrega, sin más.
