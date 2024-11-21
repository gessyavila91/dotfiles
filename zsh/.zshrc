# Cargar Oh My Posh con el tema personalizado
eval "$(oh-my-posh init zsh --config /opt/homebrew/opt/oh-my-posh/themes/gessyXdracula.omp.json)"

source ~/.config/zsh/aliases.zsh
source ~/.config/zsh/functions.zsh
source ~/.config/zsh/plugins.zsh

export PATH="/Users/gessyavila/.config/herd-lite/bin:$PATH"
export PHP_INI_SCAN_DIR="/Users/gessyavila/.config/herd-lite/bin:$PHP_INI_SCAN_DIR"
