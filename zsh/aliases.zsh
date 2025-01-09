# Crear cdtree para ejecutar tree después de cambiar de directorio
alias cdtree='builtin cd "$@" && lsd --tree --depth 2'

# Aliases for common dirs
alias home="cd ~ && lsd"
# Alias para `ls`
alias ls='lsd'
alias la='ls -a'
alias lsl='ls -l'

# Alias para mostrar dos niveles de profundidad como un árbol
alias lstree='tree -L 2'

#
alias cat='bat --style=numbers,changes'

# Copy actual path to clipboard
alias cpydir='pwd | pbcopy && echo "The current directory path has been copied to the clipboard."'

# lazy yabairc reload
alias yabairld='source ~/.config/yabai/yabairc'

# Laravel/Sail alias
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'