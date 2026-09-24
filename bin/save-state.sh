#!/bin/bash
# Guarda el estado del plugin. Sin privilegios: solo escribe el archivo que
# el helper root (legion-power-helper.sh) va a leer via pkexec.
#
# R9 (AGENTS.md): recibe todo como argumentos posicionales, nunca interpola
# valores de settings en un string de comando armado a mano. Quien invoca
# esto (service/Main.qml) pasa cada valor como un elemento separado de argv.
set -euo pipefail

STATE_FILE="$1"
WATTS="$2"
FREQPCT="$3"
MODE="$4"
FANPWM="$5"

mkdir -p "$(dirname "$STATE_FILE")"

{
    printf 'watts=%s\n' "$WATTS"
    printf 'freqpct=%s\n' "$FREQPCT"
    printf 'mode=%s\n' "$MODE"
    printf 'fanpwm=%s\n' "$FANPWM"
} > "$STATE_FILE"
