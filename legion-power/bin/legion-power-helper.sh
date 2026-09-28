#!/bin/bash
# Helper privilegiado invocado via pkexec. Un solo comando fijo sin
# argumentos variables (Ryoku exige coincidencia exacta contra
# capabilities.privileged). El valor real se lee de un archivo de
# estado persistente, escrito sin privilegios antes de llamar aqui.
set -euo pipefail

# R8: debe apuntar exactamente a donde pluginApi.stateDir resuelve para este
# plugin (típicamente $XDG_STATE_HOME/ryoku/plugins/<id>, y XDG_STATE_HOME
# por defecto es ~/.local/state). Si el valor real de pluginApi.stateDir no
# coincide con esta ruta en tu instalación, hay que actualizarla aca.
STATE_FILE="/home/astrixx/.local/state/ryoku/plugins/legion-power/state"
PROFILE_PATH=/sys/class/platform-profile/platform-profile-0/profile

# Umbrales de temperatura FIJOS de la curva (no editables desde la grafica,
# solo el PWM de cada punto es configurable por el usuario).
TEMP=(35 42 47 50 55 60 65 70 85 100)
HYST=(30 35 40 45 50 55 60 65 75 90)

read_kv() {
    grep "^$1=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-
}

apply_fancurve() {
    local pwm_csv="$1"
    IFS=',' read -ra PCT <<< "$pwm_csv"
    if [ "${#PCT[@]}" -ne 10 ]; then return 0; fi

    HWMON=$(dirname $(grep -l legion_hwmon /sys/class/hwmon/hwmon*/name))
    MAX_PASSES=8
    for pass in $(seq 1 $MAX_PASSES); do
        all_ok=1
        for i in $(seq 1 10); do
            t=${TEMP[$((i-1))]}; h=${HYST[$((i-1))]}
            pct=${PCT[$((i-1))]}
            p=$(( pct * 255 / 100 ))
            for fan in 1 2; do
                pwm_file="$HWMON/pwm${fan}_auto_point${i}_pwm"
                cur=$(cat "$pwm_file" 2>/dev/null || echo -1)
                if [ "$cur" != "$p" ]; then
                    echo "$t" > "$HWMON/pwm${fan}_auto_point${i}_temp" 2>/dev/null || true
                    echo "$h" > "$HWMON/pwm${fan}_auto_point${i}_temp_hyst" 2>/dev/null || true
                    echo "$p" > "$pwm_file" 2>/dev/null || true
                    all_ok=0
                fi
            done
        done
        [ "$all_ok" = "1" ] && break
        sleep 0.3
    done
}

case "${1:-}" in
  apply)
    watts=$(read_kv watts)
    freqpct=$(read_kv freqpct)
    mode=$(read_kv mode)
    fanpwm=$(read_kv fanpwm)

    if [[ "$watts" =~ ^[0-9]+$ ]]; then
        echo $((watts * 1000000)) > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
    fi
    if [[ "$freqpct" =~ ^[0-9]+$ ]] && [ "$freqpct" -ge 1 ] && [ "$freqpct" -le 100 ]; then
        echo "$freqpct" > /sys/devices/system/cpu/intel_pstate/max_perf_pct
    fi
    case "$mode" in
      low-power|balanced|performance|max-power|custom)
        echo "$mode" > "$PROFILE_PATH"
        ;;
    esac
    if [ -n "$fanpwm" ]; then
        apply_fancurve "$fanpwm"
    fi
    ;;
  *)
    echo "accion desconocida" >&2
    exit 1
    ;;
esac
