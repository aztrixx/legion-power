pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
    id: svc

    property var pluginApi
    readonly property var settings: pluginApi ? pluginApi.pluginSettings : null

    // R1/R6: este path DEBE coincidir con donde `ryoku plugin add` copia el
    // plugin — confirmado que copia (no symlink) a
    // ~/.local/share/ryoku/plugins/<id>/, nunca al directorio de desarrollo
    // en ~/Documentos/ryoku-plugins/<id>/. Si reinstalás con `ryoku plugin
    // remove` + `ryoku plugin add`, este string y el de manifest.json
    // (capabilities.privileged) tienen que seguir siendo idénticos entre sí.
    readonly property string helperPath: "/home/astrixx/.local/share/ryoku/plugins/legion-power/bin/legion-power-helper.sh"

    // R8: escribir solo bajo pluginApi.stateDir (nunca una ruta inventada
    // como ~/.config/legion-power). El lado sin privilegios puede leer esto
    // de pluginApi directamente; el helper root (bin/legion-power-helper.sh)
    // no puede, así que ahí el mismo path queda como literal fijo — debe
    // mantenerse en sync con lo que resuelva pluginApi.stateDir.
    readonly property string pluginDir: pluginApi ? pluginApi.pluginDir : ""
    readonly property string configDir: pluginApi ? pluginApi.stateDir : ""
    readonly property string stateFile: svc.configDir + "/state"

    // --- Preferencias del usuario (persistentes, editables en el panel) ---
    property int watts: 65
    property int freqMaxPct: 100
    property string pendingMode: "custom"
    property var fanPwm: [20, 30, 50, 50, 60, 70, 80, 100, 100, 100]
    readonly property var fanTemps: [35, 42, 47, 50, 55, 60, 65, 70, 85, 100]

    // --- Estado real leido del sistema (solo lectura) ---
    property string liveMode: "custom"
    property real liveFreqGHz: 0
    property real liveTempC: 0
    property bool applying: false
    property bool loaded: false

    readonly property var modeColors: ({
        "low-power": "#378ADD",
        "balanced": "#e8e8e6",
        "performance": "#E24B4A",
        "custom": "#B96FE0"
    })
    readonly property color currentColor: modeColors[svc.liveMode] ?? "#8b8c90"

    function resetFanCurve() {
        svc.fanPwm = [20, 30, 50, 50, 60, 70, 80, 100, 100, 100];
    }

    // --- Cargar preferencias guardadas al arrancar (sin privilegios: es
    // nuestro propio archivo de config, no un archivo del sistema) ---
    Process {
        id: loadProc
        command: svc.stateFile !== "" ? ["cat", svc.stateFile] : ["true"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var i = data.indexOf("=");
                if (i < 0) return;
                var k = data.substring(0, i);
                var v = data.substring(i + 1);
                if (k === "watts" && /^[0-9]+$/.test(v)) svc.watts = parseInt(v);
                else if (k === "freqpct" && /^[0-9]+$/.test(v)) svc.freqMaxPct = parseInt(v);
                else if (k === "mode") svc.pendingMode = v;
                else if (k === "fanpwm") {
                    var parts = v.split(",").map(x => parseInt(x));
                    if (parts.length === 10 && parts.every(x => !isNaN(x))) svc.fanPwm = parts;
                }
            }
        }
        onExited: svc.loaded = true
    }
    Component.onCompleted: loadProc.running = true
    // Salvaguarda: si pluginApi (y por lo tanto stateDir) llega despues del
    // primer intento, reintenta la carga en vez de quedarse con stateFile="".
    onPluginApiChanged: { if (svc.pluginApi && !svc.loaded) loadProc.running = true; }

    // --- Lectura en vivo, sin privilegios ---
    Process {
        id: readProc
        command: ["bash", "-c",
            "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; " +
            "sensors | grep 'CPU Temperature' | grep -oP '\\+\\K[0-9.]+' | head -1"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var d = data.trim();
                if (d === "") return;
                if (d.includes(".")) svc.liveTempC = parseFloat(d);
                else if (/^[0-9]+$/.test(d)) svc.liveFreqGHz = parseInt(d) / 1000000;
            }
        }
    }
    function refreshStats() {
        if (!readProc.running) readProc.running = true;
    }

    // --- Vigilancia del perfil real, SIEMPRE activa (sin privilegios),
    // para sincronizar el anillo con Fn+Q y reaplicar solo al entrar a
    // custom desde otro modo. ---
    property string _prevLiveMode: "custom"
    Process {
        id: modeWatchProc
        command: ["cat", "/sys/class/platform-profile/platform-profile-0/profile"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var d = data.trim();
                if (["low-power", "balanced", "performance", "max-power", "custom"].indexOf(d) === -1) return;
                var was = svc._prevLiveMode;
                svc.liveMode = d;
                if (was !== "custom" && d === "custom" && svc.loaded) {
                    svc.applyAll();
                }
                svc._prevLiveMode = d;
            }
        }
    }
    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!modeWatchProc.running) modeWatchProc.running = true; }
    }

    // --- Guardar + aplicar. Un solo comando pkexec fijo. ---
    Process {
        id: writeStateProc
        onExited: (exitCode, exitStatus) => {
            applyProc.command = ["pkexec", "/home/astrixx/.local/share/ryoku/plugins/legion-power/bin/legion-power-helper.sh", "apply"];
            applyProc.running = true;
        }
    }
    Process {
        id: applyProc
        onExited: (exitCode, exitStatus) => { svc.applying = false; }
    }

    function applyAll() {
        svc.applying = true;
        // R9: nunca interpolar valores de settings en un string de "bash -c".
        // Se pasan como argv a un script propio sin privilegios que hace su
        // propio quoting con printf "%s".
        writeStateProc.command = [svc.pluginDir + "/bin/save-state.sh",
            svc.stateFile,
            String(svc.watts),
            String(svc.freqMaxPct),
            svc.pendingMode,
            svc.fanPwm.join(",")];
        writeStateProc.running = true;
    }
}
