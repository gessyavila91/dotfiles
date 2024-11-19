#!/usr/bin/env sh

# battery
sketchybar --add item battery right                                 \
--set      battery icon=􀛨                \
                   icon.color=${green}                   \
                   background.border_color=${green}      \
                   label="--%"                           \
                   script="$PLUGIN_DIR/battery.sh"       \
                   update_freq=120
