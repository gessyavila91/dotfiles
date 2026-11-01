#!/bin/sh
# Hook SessionStart de Claude Code (P5b §4.3): inyecta el resumen breve de pendientes.
# Límite de 2 s con vigilante en segundo plano (macOS no trae `timeout`).
# Siempre sale con 0; sin nada que decir (o ante cualquier fallo) no imprime nada.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

BIN=${EST_BIN:-"$HOME/.claude/skills/estado/estado.sh"}
[ -f "$BIN" ] || exit 0

DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$DIR" ] || DIR=$(pwd)

TMP=$(mktemp "${TMPDIR:-/tmp}/estado-session.XXXXXX") || exit 0
WPID=""; WDOG=""
cleanup() {
  [ -n "$WDOG" ] && { pkill -P "$WDOG" 2>/dev/null; kill "$WDOG" 2>/dev/null; { wait "$WDOG"; } 2>/dev/null; }
  [ -n "$WPID" ] && { pkill -P "$WPID" 2>/dev/null; kill "$WPID" 2>/dev/null; { wait "$WPID"; } 2>/dev/null; }
  rm -f "$TMP" "$TMP.to"
}
trap cleanup EXIT

sh "$BIN" --breve "$DIR" >"$TMP" 2>/dev/null &
WPID=$!
(
  sleep 2
  : >"$TMP.to"
  pkill -P "$WPID" 2>/dev/null
  kill "$WPID" 2>/dev/null
) >/dev/null 2>&1 &
WDOG=$!

wait "$WPID" 2>/dev/null
RC=$?
[ ! -e "$TMP.to" ] || exit 0
[ "$RC" -eq 0 ] || exit 0

SUMMARY=$(cat "$TMP")
[ -n "$SUMMARY" ] || exit 0

jq -n --arg c "$SUMMARY" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null
exit 0
