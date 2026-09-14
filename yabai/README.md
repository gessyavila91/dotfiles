# yabai — mantenimiento

Runbook operativo. Para la config en sí, ver `yabairc`.

Estado de referencia (13 sep 2026): yabai 7.1.25, servicio `com.asmvik.yabai`,
123 reglas / 3 señales, scripting addition cargada.

---

## ⚠️ Después de CADA `brew upgrade yabai`

**Se rompe la scripting addition, en silencio.** Es el fallo más importante de
esta carpeta y no avisa de ninguna forma visible.

`/etc/sudoers.d/yabai` autoriza `yabai --load-sa` sin password, pero la regla
está atada al **SHA-256 del binario**. Cada upgrade escribe un binario nuevo con
otro hash, la regla deja de coincidir y sudo vuelve a pedir password. Como yabai
lo arranca launchd, que no tiene terminal, la carga falla y `yabairc` **sigue
corriendo tranquilamente**: tilea, aplica gaps y las 123 reglas. Todo parece
normal.

Lo único que se pierde es la manipulación de espacios:

| Binding (skhd) | Comando | Depende de la SA |
|---|---|---|
| `alt - n` | `space --create` | sí |
| `shift + alt - n` | `space --create` + `window --space` | sí |
| `cmd + alt - q` | `space --destroy` | sí |

### Arreglo

Pegar en una terminal real (Ghostty). **No funciona con el `!` de Claude Code ni
por SSH sin TTY** — sudo necesita terminal para pedir el password.

```sh
printf '%s\n' "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 "$(which yabai)" | cut -d' ' -f1) $(which yabai) --load-sa" > /tmp/yabai.sudoers
sudo visudo -c -f /tmp/yabai.sudoers \
  && sudo install -m 440 -o root -g wheel /tmp/yabai.sudoers /etc/sudoers.d/yabai \
  && rm /tmp/yabai.sudoers \
  && yabai --restart-service
```

Valida con `visudo -c` **antes** de instalar. Un `sudoers.d` malformado rompe
sudo por completo; si la validación falla la cadena se corta y el archivo actual
queda intacto.

---

## Checks post-upgrade

```sh
# 1. ¿La regla NOPASSWD coincide con el binario actual?
sudo -n -l | grep load-sa
shasum -a 256 "$(which yabai)" | cut -d' ' -f1
#    -> los dos hashes deben ser IGUALES

# 2. ¿Pasa sin password? (exit 0 y sin salida = ok)
sudo -n yabai --load-sa; echo "exit: $?"

# 3. ¿Errores de sudo al arrancar? (debe salir vacío)
cat /tmp/yabai_$USER.err.log

# 4. ¿Se aplicó yabairc?
yabai -m rule --list   | jq 'length'   # -> 123
yabai -m signal --list | jq 'length'   # -> 3
yabai -m config layout                 # -> bsp
yabai -m config external_bar           # -> all:36:3

# 5. ¿Un solo proceso y un solo launch agent?
pgrep -f 'bin/yabai' | wc -l           # -> 1
ls ~/Library/LaunchAgents | grep -i yabai   # -> solo com.asmvik.yabai.plist
```

Si (4) devuelve `0/0` y `layout float`, yabairc no se aplicó: ir a
[Diagnóstico](#diagnóstico).

---

## Diagnóstico

### `rules: 0`, `signals: 0`, `layout float`, gaps en 0

yabai corre con defaults puros: `yabairc` no se ejecutó, o se ejecutó sin poder
encontrar el binario `yabai`.

Causa habitual: **un launch agent duplicado**. Si hay dos plists arrancando
yabai, ambos se pegan al mismo socket (`/tmp/yabai_$USER.socket`) y el último
en enlazar es el que responde a `yabai -m`. Si ese agent no define `PATH` en
`EnvironmentVariables`, launchd le da el mínimo (`/usr/bin:/bin:/usr/sbin:/sbin`),
sin `/opt/homebrew/bin` — y **todas** las líneas de yabairc fallan con
`yabai: command not found`.

```sh
launchctl list | grep -i yabai        # debe haber UNA sola entrada
lsof -U | grep yabai                  # debe haber UN solo proceso en el socket
```

Para reproducir el fallo y confirmarlo:

```sh
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh ~/.config/yabai/yabairc 2>&1 | head
```

### `service file 'com.asmvik.yabai.plist' is not installed! abort..`

El plist tiene el label de la era `koekeishiya` y el binario actual busca
`com.asmvik.yabai`. El proyecto se mudó de `koekeishiya/yabai` a `asmvik/yabai`.
Migrar:

```sh
launchctl bootout gui/$UID/com.koekeishiya.yabai
rm ~/Library/LaunchAgents/com.koekeishiya.yabai.plist
yabai --start-service
```

`--start-service` graba el `PATH` del shell actual dentro del plist. Generarlo
solo desde un shell con PATH sano.

### El socket muere al quitar un agent

Si se hace `bootout` del proceso que tenía el socket, el otro queda vivo pero
incomunicado (`yabai-msg: failed to connect to socket`). Se arregla con
`launchctl kickstart -k gui/$UID/com.asmvik.yabai`.

---

## Recomendaciones

**Nunca `source` este archivo.** `rule --add` y `signal --add` no reemplazan:
apilan. Cada `source ~/.config/yabai/yabairc` añade otras ~116 reglas y 3
señales sobre la instancia viva (solo las que llevan `label=` se deduplican), y
yabai las evalúa todas en cada ventana creada. Además dispara el prompt de sudo
y deja `apply_yabai_config` / `add_yabai_rules` colgando en el shell.

Para recargar siempre:

```sh
yabai --restart-service     # alias: yabairld
```

**Un solo launch agent.** Respaldos de los dos plists retirados en
`~/.config/_disabled_launchagents/`.

**`brew upgrade` puede quedar bloqueado.** Homebrew 7.x exige confiar los taps
de terceros antes de cargar sus fórmulas. Si sale
`Refusing to load formula ... from untrusted tap`:

```sh
brew trust --formula koekeishiya/formulae/yabai
```

Un paquete sin confianza no falla ruidosamente: brew simplemente **deja de
verlo** en `outdated` y `upgrade`.
