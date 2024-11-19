#!/usr/bin/env sh

APPLE=(
  icon=$APPLE_ICON
  icon.color=${foreground}
  icon.padding_left=4
  label.drawing=off
  background.padding_left=0
  background.padding_right=22
  background.color=$BG_PRI_CLOR
)

sketchybar --add item apple left \
           --set apple "${APPLE[@]}"