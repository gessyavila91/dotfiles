# Redefinir cd para ejecutar ls -a después
function cd() {
    builtin cd "$@" && ls
}