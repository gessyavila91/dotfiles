#!/usr/bin/env sh

# Cargar Oh My Posh con el tema personalizado
eval "$(oh-my-posh init zsh --config /opt/homebrew/opt/oh-my-posh/themes/gessyXdracula.omp.json)"
eval "$(/opt/homebrew/bin/brew shellenv)"

source ~/.config/zsh/aliases.zsh
source ~/.config/zsh/functions.zsh
source ~/.config/zsh/plugins.zsh

export PHP_INI_SCAN_DIR="/Users/gessyavila/.config/herd-lite/bin:$PHP_INI_SCAN_DIR"

export PATH="/path/to/arm-none-eabi-gcc/bin:/Users/gessyavila/.config/herd-lite/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
