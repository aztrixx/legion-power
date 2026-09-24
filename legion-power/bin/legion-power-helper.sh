#!/bin/bash
# Helper privilegiado invocado via pkexec. Un solo comando fijo sin
# argumentos variables (Ryoku exige coincidencia exacta contra
# capabilities.privileged). El valor real se lee de un archivo de
# estado persistente, escrito sin privilegios antes de llamar aqui.
set -euo pipefail

PLUGIN_ID="legion-power"

# R8: pkexec limpia el entorno, asi que aqui no existe XDG_STATE_HOME. Se
# resuelve el home del usuario que lanzo pkexec (PKEXEC_UID) y se usa el
# valor por defecto de pluginApi.stateDir: ~/.local/state/ryoku/plugins/<id>.
# Si tu XDG_STATE_HOME es distinto, cambia STATE_FILE aqui abajo.
if [ -n "${PKEXEC_UID:-}" ]; then
    USER_HOME=$(getent passwd "$PKEXEC_UID" | cut -d: -f6 || true)
else
    USER_HOME="${HOME:-}"
fi
if [ -z "$USER_HOME" ]; then
    echo "no se pudo resolver el home del usuario" >&2
    exit 1
fi
STATE_FILE="$USER_HOME/.local/state/ryoku/plugins/$PLUGIN_ID/state"
PROFILE_PATH=/sys/class/platform-profile/platform-profile-0/profile

# Umbrales de temperatura FIJOS de la curva (no editables desde la grafica,
# solo el porcentaje de cada punto es configurable).
TEMP=(35 42 47 50 55 60 65 70 85 100)
HYST=(30 35 40 45 50 55 60 65 75 90)

# Techo real de RPM de los ventiladores (medido en el equipo del autor: unos
# 4400 RPM el ventilador 1 y 4500 el 2). El driver legion_laptop escala la
# curva con un maximo generico (fan1_max = 10000 RPM) que el ventilador nunca
# alcanza. Los porcentajes de la grafica se calculan contra FAN_REAL_MAX_RPM
# para que 100% = 4400 RPM reales. Ajustalo si tu equipo llega a otro valor.
FAN_REAL_MAX_RPM=4400
FAN_DRIVER_MAX_DEFAULT=10000

read_kv() {
    grep "^$1=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

apply_fancurve() {
    local pwm_csv="$1"
    IFS=',' read -ra PCT <<< "$pwm_csv"
    if [ "${#PCT[@]}" -ne 10 ]; then return 0; fi

    # El archivo de estado lo escribe el usuario y este script corre como
    # root: cada valor debe ser un entero 0-100 antes de usarlo en aritmetica.
    local v
    for v in "${PCT[@]}"; do
        if ! [[ "$v" =~ ^[0-9]{1,3}$ ]] || [ "$v" -gt 100 ]; then
            echo "curva de ventiladores invalida, se ignora" >&2
            return 0
        fi
    done

    local hwmon_name
    hwmon_name=$(grep -l legion_hwmon /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 || true)
    if [ -z "$hwmon_name" ]; then
        echo "no encuentro legion_hwmon (esta cargado el driver legion_laptop?)" >&2
        return 0
    fi
    HWMON=$(dirname "$hwmon_name")

    DRIVER_MAX=$(cat "$HWMON/fan1_max" 2>/dev/null || echo "$FAN_DRIVER_MAX_DEFAULT")
    if ! [[ "$DRIVER_MAX" =~ ^[0-9]+$ ]] || [ "$DRIVER_MAX" -lt 1 ]; then
        DRIVER_MAX=$FAN_DRIVER_MAX_DEFAULT
    fi

    MAX_PASSES=8
    for pass in $(seq 1 $MAX_PASSES); do
        all_ok=1
        for i in $(seq 1 10); do
            t=${TEMP[$((i-1))]}; h=${HYST[$((i-1))]}
            pct=$((10#${PCT[$((i-1))]}))
            # % de FAN_REAL_MAX_RPM -> escala PWM 0-255 del driver (redondeo al mas cercano)
            p=$(( (pct * FAN_REAL_MAX_RPM * 255 + DRIVER_MAX * 50) / (DRIVER_MAX * 100) ))
            if [ "$p" -gt 255 ]; then p=255; fi
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
    if [ ! -r "$STATE_FILE" ]; then
        echo "no existe el archivo de estado: $STATE_FILE" >&2
        exit 1
    fi
    watts=$(read_kv watts)
    freqpct=$(read_kv freqpct)
    mode=$(read_kv mode)
    fanpwm=$(read_kv fanpwm)

    if [[ "$watts" =~ ^[0-9]{1,3}$ ]]; then
        echo $((10#$watts * 1000000)) > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw \
            || echo "aviso: no se pudo fijar PL1" >&2
    fi
    if [[ "$freqpct" =~ ^[0-9]{1,3}$ ]] && [ "$freqpct" -ge 1 ] && [ "$freqpct" -le 100 ]; then
        echo "$((10#$freqpct))" > /sys/devices/system/cpu/intel_pstate/max_perf_pct \
            || echo "aviso: no se pudo fijar el techo de frecuencia" >&2
    fi
    case "$mode" in
      low-power|balanced|performance|max-power|custom)
        echo "$mode" > "$PROFILE_PATH" || echo "aviso: no se pudo cambiar el modo" >&2
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
