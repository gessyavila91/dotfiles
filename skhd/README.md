# skhd — mantenimiento

Runbook operativo. Para los atajos en sí, ver `skhdrc`.

Estado de referencia (13 sep 2026): skhd 0.3.9, servicio `com.koekeishiya.skhd`,
61 bindings, sin errores de parseo.

---

## Checks post-upgrade

```sh
# 1. Servicio vivo (UNA sola entrada)
launchctl list | grep -i skhd
pgrep -f 'bin/skhd' | wc -l            # -> 1

# 2. ¿Cargó el archivo correcto y sin errores?
head -2 /tmp/skhd_$USER.out.log
#    -> skhd: using config '/Users/<user>/.config/skhd/skhdrc'
grep -iE "error|expected" /tmp/skhd_$USER.out.log   # -> vacío

# 3. ¿Config compitiendo? (debe NO existir)
ls ~/.skhdrc

# 4. Bindings duplicados (debe salir vacío)
grep -vE '^\s*#|^\s*$' skhdrc | grep ':' | sed 's/:.*//;s/[[:space:]]//g' | sort | uniq -d
```

En el log verbose, `hotkey :: #N` usa **N = número de línea** del `skhdrc`. Sirve
para localizar un binding que no cargó. Ojo: launchd bufea ese stdout y suele
cortarlo a media lista — que un binding no aparezca **no** prueba que falle.

---

## Si un atajo no responde

La gran mayoría de los 61 bindings son `yabai -m ...`, así que casi siempre el
problema está en yabai, no en skhd.

**Atajos de espacios muertos** (`alt - n`, `shift + alt - n`, `cmd + alt - q`):
la scripting addition de yabai no está cargada. Ver `../yabai/README.md` — pasa
en cada `brew upgrade yabai` y no avisa.

**`ctrl + alt + cmd - r` no reinicia yabai:** el plist de yabai tiene un label
que su binario ya no reconoce. Ver `../yabai/README.md`.

**Todo lo de ventanas raro:** comprobar que haya un solo proceso de yabai
(`pgrep -f 'bin/yabai' | wc -l` → 1). Con dos instancias, la que responde puede
ser una sin config.

Para ver qué contesta yabai a un binding, ejecutar su comando a mano:

```sh
tail -f /tmp/yabai_$USER.err.log
```

Mensajes como `could not locate a westward managed window` o
`cannot mirror a non-managed space` son **respuestas normales** de yabai cuando
el binding no aplica (borde de pantalla, ventana flotante). No son errores de
config.

---

## Recargar

```sh
skhd --restart-service
```

`skhd --reload` puede fallar con `could not locate existing instance` si el
pidfile (`/tmp/skhd_$USER.pid`) quedó apuntando a un proceso muerto — típico
tras haber lanzado una instancia suelta a mano. `--restart-service` lo regenera.

**No lanzar skhd a mano para "probar"**: sin `--start-service` se queda en
foreground y pisa el pidfile de la instancia real. `skhd` no tiene flag de
validación de sintaxis; para revisar la config, leer el `out.log` tras reiniciar.

---

## Recomendaciones

**Separadores en bindings de varios comandos.** Concatenar dos invocaciones sin
separador hace que la segunda se trague como argumentos de la primera:

```sh
# MAL — yabai responde: unknown command 'yabai' for domain 'window'
ctrl + alt - j : yabai -m window --resize left:-20:0  yabai -m window --resize right:-20:0

# BIEN — la segunda solo actúa si la primera falla (ventana en el borde)
ctrl + alt - j : yabai -m window --resize left:-20:0 || yabai -m window --resize right:-20:0
```

Preferir `||` sobre `;` en los resize: con `;` corren ambos, y una ventana con
vecinos a los dos lados se **desplaza** en vez de crecer.

**`brew upgrade` puede quedar bloqueado.** Homebrew 7.x exige confiar los taps de
terceros. Si sale `Refusing to load formula ... from untrusted tap`:

```sh
brew trust --formula koekeishiya/formulae/skhd
```

Sin confianza, brew deja de ver el paquete en `outdated` y `upgrade` — en
silencio, sin marcarlo como fallo.
