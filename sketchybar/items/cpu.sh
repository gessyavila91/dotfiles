#!/bin/bash
CPU=(
  update_freq=5
  icon.font="$FONT:Regular:16.0"
  icon=
  icon.color=${pink}
  script="$PLUGIN_DIR/cpu.sh"
)

sketchybar --add item cpu right \
           --set cpu "${CPU[@]}"
