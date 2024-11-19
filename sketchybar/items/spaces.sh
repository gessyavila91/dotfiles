#!/bin/bash
# 󰘳
SPACE_ICONS=("~ 0" "󰘳 1" "󰘳 2" "󰘳 3" "󰘳 4" "󰘳 5" "󰘳 6" "󰘳 7" "󰘳 8" "󰘳 9" "󰘳 10")

for i in "${!SPACE_ICONS[@]}"
do
  sid="$(($i+1))"
  space=(
    icon="${SPACE_ICONS[i]}"
    icon.highlight_color${purple}
    space="$sid"
    label.drawing=off
    click_script="yabai -m space --focus $sid"
  )

  sketchybar --add space space."$sid" left \
    --set space."$sid" "${space[@]}"

done
# create new space button
sketchybar --add item new_space left     \
           --set new_space icon.width=24 \
           --set new_space click_script="$PLUGIN_DIR/new_space.sh" \
           label.padding_right=2         \
           icon.align=center             \
           icon.padding_right=2          \
           icon=
#           click_script="$PLUGIN_DIR/new_space.sh"

# focus app chevron
sketchybar --add item chevron left \
  --set new_space icon.width=24 \
  --set chevron icon=󰛂 label.drawing=off \
  --add item front_app left \
  --set front_app icon.drawing=off script="$PLUGIN_DIR/front_app.sh" \
  --subscribe front_app front_app_switched

# consolidate space numbers and add a background
sketchybar --add bracket spaces '/space\..*/' new_space                \
           --set         spaces background.color=0xEB1e1e2e            \
                                background.corner_radius=15            \
                                background.border_width=1              \
                                background.border_color=${cyan}        \
                                blur_radius=2                          \
                                background.height=30

