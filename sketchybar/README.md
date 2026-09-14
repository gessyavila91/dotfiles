# 🚀 SketchyBar Lua Configuration

A modern, feature-rich configuration for [SketchyBar](https://felixkratz.github.io/SketchyBar) using the Lua plugin system. This configuration provides a clean, informative, and customizable menu bar experience for macOS.

## ✨ Features

- 🎨 **Modern Design**
  - Clean and minimal aesthetic with blur effects
  - Fully customizable colors and transparency
  - Rounded corners with dynamic borders
  - Consistent spacing and padding system

- 📊 **System Monitoring**
  - Real-time CPU usage tracking
  - Memory utilization metrics
  - Network traffic monitoring (up/down)
  - Battery status with charging indicators
  - Disk usage tracking

- 🎵 **Media Controls**
  - Current track information
  - Dynamic album artwork display
  - Media player controls
  - Support for multiple players:
    - Spotify
    - Music
    - Brave Browser

- 🔔 **Smart Notifications**
  - Homebrew updates counter
  - Mail notifications
  - Message indicators
  - System alerts
  - Volume and audio device controls

- 🖥️ **Workspace Management**
  - Dynamic space indicators
  - Active application tracking
  - Custom application icons
  - Window management integration
  - Space labels and navigation

## 🛠️ Prerequisites

- macOS
- [Homebrew](https://brew.sh)
- [Lua](https://www.lua.org)
- [SketchyBar](https://felixkratz.github.io/SketchyBar)
- [SbarLua](https://github.com/FelixKratz/SbarLua)

## 📦 Key Components

### Core Files
- `sketchybarrc` - Main entry point (Lua)
- `init.lua` - Initial configuration and module loading
- `bar.lua` - Bar appearance and behavior settings
- `colors.lua` - Color scheme definitions
- `settings.lua` - General configuration settings
- `icons.lua` - Icon definitions (SF Symbols/NerdFont)

### Modules
- **System Widgets** - CPU, Memory, Battery, Network monitoring
- **Media Controls** - Music player integration and controls
- **Space Management** - Workspace organization and navigation
- **Application Tracking** - Active window and application monitoring
- **Notification Center** - System and application notifications

## 🎨 Customization

The configuration is highly modular and customizable through:
- Color schemes
- Font selections
- Icon sets (SF Symbols or NerdFont)
- Layout adjustments
- Widget behavior
- Event triggers

## 🔧 Event System

Built-in C-based event providers for:
- CPU monitoring
- Memory usage
- Network traffic
- Disk usage
- Weather information

## 📚 Additional Resources

- [SketchyBar Documentation](https://felixkratz.github.io/SketchyBar/config/getting-started)
- [Lua Documentation](https://www.lua.org/docs.html)
- [SbarLua Wiki](https://github.com/FelixKratz/SbarLua/wiki)

## 🙏 Credits

- [SketchyBar](https://felixkratz.github.io/SketchyBar) by Felix Kratz
- [SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

# 🔧 Mantenimiento

Estado de referencia (13 sep 2026): sketchybar 2.24.0, servicio `sh.brew.sketchybar`,
72 items, SbarLua en `~/.local/share/sketchybar_lua/`.

## ⚠️ SbarLua no es un paquete de brew

Esta config es la variante Lua: `sketchybarrc` hace `require("sketchybar")`, que
es un módulo nativo en C (**SbarLua**) que se instala **aparte** de sketchybar y
que `brew upgrade` no toca ni repara.

Si falta, el intérprete Lua muere en la primera línea de `init.lua` y la barra
queda **con cero items**. El proceso de sketchybar sigue vivo y aparentemente
sano, así que el síntoma es una barra vacía o directamente invisible, sin ningún
error a la vista.

Dos cosas tienen que estar bien:

1. El `.so` existe en `~/.local/share/sketchybar_lua/sketchybar.so`
2. `sketchybarrc` añade esa ruta al `package.cpath` **antes** de los `require`

```lua
package.cpath = package.cpath .. ";" .. os.getenv("HOME") .. "/.local/share/sketchybar_lua/?.so"
```

Esa línea es obligatoria. SbarLua cambió su ruta de instalación: antes usaba
`~/.local/share/lua/5.4/`, que sí estaba en el `cpath` por defecto; hoy usa
`~/.local/share/sketchybar_lua/`, que no.

### Reinstalar SbarLua

```sh
git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua \
  && (cd /tmp/SbarLua && make install) \
  && rm -rf /tmp/SbarLua
```

Trae su propio Lua bundleado, así que no depende de la versión de `brew lua`.

## Checks post-upgrade

```sh
# 1. ¿La barra tiene items? (0 = SbarLua roto)
sketchybar --query bar | jq '.items | length'   # -> 72
sketchybar --query bar | jq -r '.drawing'       # -> on

# 2. ¿Corre el intérprete Lua? (sin esto no hay callbacks)
pgrep -f 'lua .*sketchybarrc'

# 3. ¿SbarLua presente?
ls -la ~/.local/share/sketchybar_lua/sketchybar.so

# 4. Servicio
brew services list | grep sketchybar
```

Si (1) devuelve `0` y (2) no encuentra nada, es SbarLua. Confirmarlo con:

```sh
lua -e 'print(pcall(require, "sketchybar"))'    # -> false  module 'sketchybar' not found
```

## Recomendaciones

**Reiniciar en frío tras tocar SbarLua.** `sketchybar --reload` solo recarga la
config; para validar que todo arranca solo tras un reboot hay que usar
`brew services restart sketchybar`.

**Los helpers se recompilan en cada carga.** `helpers/init.lua` compila los event
providers y los menu helpers al arrancar; ver `Compiling menu helpers... ✓` en el
log es normal, no un error.

**El log mezcla salida de yabai.** `/opt/homebrew/var/log/sketchybar/sketchybar.err.log`
recoge el stderr de los `yabai -m` que invocan los items. Mensajes como
`could not retrieve window details.` vienen de **yabai**, no de sketchybar. Para
silenciarlos, redirigir con `2>/dev/null` en los items.

**`external_bar` lo define yabai, no sketchybar.** El espacio reservado para la
barra sale de `external_bar all:36:3` en `../yabai/yabairc`. Si la barra se
solapa con las ventanas, el problema está ahí — comprobar con
`yabai -m config external_bar`.

**Confianza del tap.** Viene de `felixkratz/formulae`. Homebrew 7.x exige confiar
cada fórmula por separado:

```sh
brew trust --formula felixkratz/formulae/sketchybar
```

Sin confianza, brew deja de ver el paquete en `outdated` y `upgrade` sin avisar.