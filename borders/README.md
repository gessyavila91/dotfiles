# borders (JankyBorders) — mantenimiento

Runbook operativo. Para la config en sí, ver `bordersrc`.

Estado de referencia (13 sep 2026): corriendo (PID propio, `ppid 1`), lanzado por
el launch agent `homebrew.mxcl.borders` con `RunAtLoad` y `KeepAlive`.

---

## Checks post-upgrade

```sh
pgrep -f 'bin/borders' | wc -l    # -> 1
launchctl list | grep -i borders  # -> homebrew.mxcl.borders
borders --version
```

Reiniciar:

```sh
launchctl kickstart -k gui/$UID/homebrew.mxcl.borders
```

### Si no aparece en `brew services list`

Síntoma real de esta config: el launch agent existe y el proceso corre, pero
`brew services list` **no lista borders**. No es que el servicio esté caído — es
que brew no puede cargar la fórmula por falta de confianza (ver abajo) y por eso
tampoco puede reportar su servicio.

---

## Recomendaciones

**Confianza del tap.** Viene de `felixkratz/formulae`, el mismo tap que
sketchybar. Homebrew 7.x exige confiar cada fórmula por separado: tener
`sketchybar` confiado **no** cubre `borders`. Si sale
`Refusing to load formula ... from untrusted tap`:

```sh
brew trust --formula felixkratz/formulae/borders
```

Un paquete sin confianza desaparece de `brew outdated` y `brew upgrade` sin
avisar — no falla, simplemente deja de actualizarse.

**Los colores siguen la paleta Dracula** y están duplicados a mano en
`../sketchybar/colors.lua`. Si se cambian aquí, cambiarlos allí también.
