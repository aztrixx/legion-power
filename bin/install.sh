#!/bin/bash
# Instala legion-power en Ryoku con `ryoku plugin add`.
#
# Ryoku exige que la ruta absoluta del helper en service/Main.qml y en
# manifest.json (capabilities.privileged) sea identica. El repositorio trae la
# ruta del autor; este script copia el plugin a una carpeta temporal, cambia
# esa ruta por el home del usuario actual y valida e instala desde ahi.
# El repositorio original no se modifica.
#
# Uso:  ./bin/install.sh [--reinstall]
#   --reinstall  ejecuta antes `ryoku plugin remove legion-power`
set -euo pipefail

PLUGIN_ID="legion-power"
REPO_BASE="/home/astrixx/.local/share"   # ruta con la que viene escrito el repo
DEST_BASE="$HOME/.local/share"           # donde `ryoku plugin add` instala
REINSTALL=0

for arg in "$@"; do
    case "$arg" in
        --reinstall) REINSTALL=1 ;;
        -h|--help)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "opcion desconocida: $arg" >&2; exit 1 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }
warn() { echo "aviso: $*" >&2; }

[ "$(id -u)" -ne 0 ] || fail "no lo ejecutes como root: se instala para tu usuario."
[[ "$DEST_BASE" =~ ^[A-Za-z0-9_./-]+$ ]] \
    || fail "tu HOME tiene caracteres que este instalador no soporta: $HOME"

for cmd in ryoku pkexec sensors; do
    command -v "$cmd" >/dev/null 2>&1 || fail "falta el comando '$cmd'."
done

if ! grep -qs legion_hwmon /sys/class/hwmon/hwmon*/name; then
    warn "no veo el driver legion_laptop (legion_hwmon). El plugin se instala, pero no controlara los ventiladores hasta cargarlo."
fi
if [ -n "${XDG_STATE_HOME:-}" ] && [ "$XDG_STATE_HOME" != "$HOME/.local/state" ]; then
    warn "XDG_STATE_HOME no es ~/.local/state: edita STATE_FILE en bin/legion-power-helper.sh."
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/$PLUGIN_ID"       # Ryoku exige que la carpeta se llame como el id
mkdir -p "$PKG"
cp -a "$SRC_DIR/." "$PKG/"
rm -rf "$PKG/.git"

if [ "$DEST_BASE" != "$REPO_BASE" ]; then
    sed -i "s|${REPO_BASE//./\\.}|$DEST_BASE|g" "$PKG/manifest.json" "$PKG/service/Main.qml"
fi
HELPER_PATH="$DEST_BASE/ryoku/plugins/$PLUGIN_ID/bin/legion-power-helper.sh"
grep -qF "$HELPER_PATH" "$PKG/manifest.json" || fail "no se pudo ajustar la ruta en manifest.json."
grep -qF "$HELPER_PATH" "$PKG/service/Main.qml" || fail "no se pudo ajustar la ruta en service/Main.qml."

chmod +x "$PKG"/bin/*.sh

echo "Validando..."
ryoku plugin validate "$PKG"

if [ "$REINSTALL" -eq 1 ]; then
    echo "Quitando la version instalada..."
    ryoku plugin remove "$PLUGIN_ID" || true
fi

echo "Instalando..."
ryoku plugin add "$PKG" --bar --yes

echo "Listo. Busca 'Legion Power' en QS Bar Settings > Community."
