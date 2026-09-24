pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.PluginKit.Singletons

Item {
    id: root

    property var pluginApi
    property string density: "full"
    property real s: 1
    property real widthBudget: 420
    property bool active: false

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property bool unlocked: service ? service.pendingMode === "custom" : false

    property string currentTab: "cpu"
    property real cornerRadius: 14 * root.s

    implicitWidth: root.widthBudget
    implicitHeight: col.implicitHeight + 24 * root.s

    onActiveChanged: {
        if (root.active && root.service) {
            root.service.pendingMode = root.service.liveMode;
        }
    }

    Timer {
        interval: 2000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (root.service) root.service.refreshStats(); }
    }

    component MiniSlider: Item {
        id: sl
        property real from: 0
        property real to: 100
        property real value: 0
        property real step: 1
        property bool enabled2: true
        signal moved(real v)

        height: 6 * root.s
        opacity: enabled2 ? 1 : 0.4

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4 * root.s
            radius: height / 2
            color: Theme.cardTop
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: track.width * Math.max(0, Math.min(1, (sl.value - sl.from) / (sl.to - sl.from)))
            height: 4 * root.s
            radius: height / 2
            color: service ? service.currentColor : Theme.accent
        }
        Rectangle {
            width: 14 * root.s
            height: 14 * root.s
            radius: width / 2
            color: Theme.bright
            y: (sl.height - height) / 2
            x: track.width * Math.max(0, Math.min(1, (sl.value - sl.from) / (sl.to - sl.from))) - width / 2
        }
        MouseArea {
            enabled: sl.enabled2
            anchors.fill: parent
            anchors.margins: -8 * root.s
            onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            onPressed: mouse => { update(mouse.x); }
            function update(mx) {
                var ratio = Math.max(0, Math.min(1, mx / track.width));
                var raw = sl.from + ratio * (sl.to - sl.from);
                var stepped = Math.round(raw / sl.step) * sl.step;
                stepped = Math.max(sl.from, Math.min(sl.to, stepped));
                if (stepped !== sl.value) { sl.value = stepped; sl.moved(stepped); }
            }
        }
    }

    component SliderCard: Column {
        id: card
        property string label: ""
        property string range: ""
        property real value: 0
        property string unit: ""
        property real from: 0
        property real to: 100
        property real step: 1
        property bool enabled2: true
        signal moved(real v)

        width: parent.width
        spacing: 4 * root.s
        Text { text: card.label; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10 * root.s }
        Row {
            width: parent.width
            Text {
                text: Math.round(card.value) + card.unit
                color: card.enabled2 ? Theme.bright : Theme.dim
                font.family: Theme.font; font.pixelSize: 18 * root.s
                width: parent.width - rangeLbl.implicitWidth
            }
            Text { id: rangeLbl; text: card.range; color: Theme.dim; font.pixelSize: 11 * root.s }
        }
        MiniSlider {
            id: innerSlider
            width: parent.width
            from: card.from; to: card.to; step: card.step
            value: card.value
            enabled2: card.enabled2

            Connections {
                target: innerSlider
                function onMoved(v) { card.moved(v); }
            }
        }
    }
    // --- Grafica de curva de ventiladores ---
    component FanGraph: Item {
        id: graph
        property var temps: []
        property var pwm: []
        property bool enabled2: true
        signal pointMoved(int index, int value)

        property real gw: width - 34 * root.s
        property real gh: 170 * root.s
        opacity: enabled2 ? 1 : 0.4

        implicitHeight: gh + 22 * root.s

        function xFor(i) { return 34 * root.s + (i / (graph.temps.length - 1)) * graph.gw; }
        function yFor(v) { return graph.gh - (v / 100) * graph.gh; }

        Column {
            x: 0; y: 0
            spacing: 0
            Repeater {
                model: [100, 80, 60, 40, 20, 0]
                delegate: Text {
                    required property int modelData
                    width: 30 * root.s
                    height: graph.gh / 5
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.dim
                    font.pixelSize: 9 * root.s
                }
            }
        }

        Canvas {
            id: canvas
            x: 34 * root.s; y: 0
            width: graph.gw
            height: graph.gh
            property var pwmRef: graph.pwm
            onPwmRefChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = "#2a2b2e";
                ctx.lineWidth = 1;
                for (var g = 0; g <= 5; g++) {
                    var gy = (graph.gh / 5) * g;
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke();
                }
                if (graph.pwm.length !== graph.temps.length) return;
                ctx.strokeStyle = service ? service.currentColor : "#B96FE0";
                ctx.lineWidth = 2;
                ctx.beginPath();
                for (var i = 0; i < graph.temps.length; i++) {
                    var px = graph.xFor(i) - 34 * root.s, py = graph.yFor(graph.pwm[i]);
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.stroke();
            }
        }

        Repeater {
            model: graph.temps.length
            delegate: Rectangle {
                required property int index
                width: 14 * root.s; height: 14 * root.s; radius: width / 2
                color: Theme.bright
                x: graph.xFor(index) - width / 2
                y: graph.yFor(graph.pwm[index] !== undefined ? graph.pwm[index] : 0) - height / 2
                MouseArea {
                    enabled: graph.enabled2
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        var localY = mapToItem(graph, mouse.x, mouse.y).y;
                        var raw = (1 - (localY / graph.gh)) * 100;
                        var stepped = Math.max(0, Math.min(100, Math.round(raw / 10) * 10));
                        graph.pointMoved(index, stepped);
                    }
                }
            }
        }

        Row {
            y: graph.gh + 4 * root.s
            x: 34 * root.s
            width: graph.gw
            Repeater {
                model: graph.temps
                delegate: Text {
                    required property int modelData
                    width: graph.gw / graph.temps.length
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData + "°"
                    color: Theme.dim
                    font.pixelSize: 9 * root.s
                }
            }
        }
    }

    Column {
        id: col
        x: 14 * root.s
        y: 14 * root.s
        width: root.width - 28 * root.s
        spacing: 14 * root.s

        Item {
            width: parent.width
            height: logoImg.implicitHeight

            Image {
                id: logoImg
                anchors.horizontalCenter: parent.horizontalCenter
                source: Qt.resolvedUrl("../assets/logo.png")
                sourceSize.width: 80 * root.s
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        Row {
            spacing: 8 * root.s
            NotchedRing {
                width: 20 * root.s; height: 20 * root.s; strokeW: 3 * root.s
                ringColor: service ? service.currentColor : "#8b8c90"
                Behavior on ringColor { ColorAnimation { duration: 200 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Control de energia"
                color: Theme.bright; font.family: Theme.display; font.pixelSize: 15 * root.s
            }
        }

        Row {
            width: parent.width
            height: 34 * root.s
            Rectangle {
                width: parent.width / 2; height: parent.height
                radius: root.cornerRadius
                color: root.currentTab === "cpu" ? (service ? service.currentColor : Theme.accent) : Theme.cardTop
                Text {
                    anchors.centerIn: parent
                    text: "CPU"
                    color: root.currentTab === "cpu" ? Theme.cardBot : Theme.dim
                    font.pixelSize: 12 * root.s
                }
                MouseArea { anchors.fill: parent; onClicked: root.currentTab = "cpu" }
            }
            Rectangle {
                width: parent.width / 2; height: parent.height
                radius: root.cornerRadius
                color: root.currentTab === "fans" ? (service ? service.currentColor : Theme.accent) : Theme.cardTop
                Text {
                    anchors.centerIn: parent
                    text: "Ventiladores"
                    color: root.currentTab === "fans" ? Theme.cardBot : Theme.dim
                    font.pixelSize: 12 * root.s
                }
                MouseArea { anchors.fill: parent; onClicked: root.currentTab = "fans" }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "transparent"
            visible: !root.unlocked
            Text {
                visible: !root.unlocked
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Selecciona Custom para editar potencia, frecuencia y ventiladores"
                color: "#d9a15c"
                font.pixelSize: 11 * root.s
            }
        }

        // --- TAB CPU ---
        Column {
            width: parent.width
            spacing: 14 * root.s
            visible: root.currentTab === "cpu"

            Rectangle {
                width: parent.width
                radius: root.cornerRadius
                color: Theme.cardTop
                height: statCol.implicitHeight + 20 * root.s
                Column {
                    id: statCol
                    x: 12 * root.s; y: 10 * root.s
                    width: parent.width - 24 * root.s
                    spacing: 4 * root.s
                    Row { width: parent.width; Text { text: "Reloj"; color: Theme.dim; font.pixelSize: 12 * root.s; width: parent.width / 2 } Text { text: (service ? service.liveFreqGHz.toFixed(1) : "0.0") + " GHz"; color: Theme.bright; font.pixelSize: 12 * root.s } }
                    Row { width: parent.width; Text { text: "Temperatura"; color: Theme.dim; font.pixelSize: 12 * root.s; width: parent.width / 2 } Text { text: (service ? service.liveTempC.toFixed(0) : "0") + " °C"; color: Theme.bright; font.pixelSize: 12 * root.s } }
                }
            }

            SliderCard {
                label: "POTENCIA CPU (PL1)"
                range: "25-95 W"
                unit: " W"
                from: 25; to: 95; step: 1
                value: service ? service.watts : 65
                enabled2: root.unlocked
                onMoved: v => { if (service) service.watts = v; }
            }

            SliderCard {
                label: "TECHO DE FRECUENCIA"
                range: "40-100%"
                unit: " %"
                from: 40; to: 100; step: 1
                value: service ? service.freqMaxPct : 100
                enabled2: root.unlocked
                onMoved: v => { if (service) service.freqMaxPct = v; }
            }

            Column {
                width: parent.width
                spacing: 6 * root.s
                Text { text: "MODO"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10 * root.s }
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 8 * root.s
                    rowSpacing: 8 * root.s
                    Repeater {
                        model: [
                            { mode: "low-power", label: "Silencioso" },
                            { mode: "balanced", label: "Equilibrado" },
                            { mode: "performance", label: "Rendimiento" },
                            { mode: "custom", label: "Custom" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (col.width - 8 * root.s) / 2
                            height: 34 * root.s
                            radius: root.cornerRadius
                            color: Theme.cardTop
                            border.width: 1
                            border.color: service && service.pendingMode === modelData.mode
                                ? service.modeColors[modelData.mode] : Theme.cardTop
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: service && service.pendingMode === modelData.mode
                                    ? service.modeColors[modelData.mode] : Theme.dim
                                font.pixelSize: 12 * root.s
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { if (service) service.pendingMode = modelData.mode; }
                            }
                        }
                    }
                }
            }
        }

        // --- TAB VENTILADORES ---
        Column {
            width: parent.width
            spacing: 10 * root.s
            visible: root.currentTab === "fans"

            Rectangle {
                width: parent.width
                radius: root.cornerRadius
                color: Theme.cardTop
                height: fanStatCol.implicitHeight + 20 * root.s
                Column {
                    id: fanStatCol
                    x: 12 * root.s; y: 10 * root.s
                    width: parent.width - 24 * root.s
                    spacing: 4 * root.s
                    Row { width: parent.width; Text { text: "Temperatura"; color: Theme.dim; font.pixelSize: 12 * root.s; width: parent.width / 2 } Text { text: (service ? service.liveTempC.toFixed(0) : "0") + " °C"; color: Theme.bright; font.pixelSize: 12 * root.s } }
                }
            }

            Text { text: "CURVA DE VENTILADORES"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10 * root.s }

            Rectangle {
                width: parent.width
                radius: root.cornerRadius
                color: Theme.cardTop
                height: fanGraph.implicitHeight + 16 * root.s
                FanGraph {
                    id: fanGraph
                    x: 8 * root.s; y: 8 * root.s
                    width: parent.width - 16 * root.s
                    temps: service ? service.fanTemps : []
                    pwm: service ? service.fanPwm : []
                    enabled2: root.unlocked
                    onPointMoved: (index, value) => {
                        if (!service) return;
                        var arr = service.fanPwm.slice();
                        arr[index] = value;
                        service.fanPwm = arr;
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 30 * root.s
                radius: root.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: Theme.cardTop
                opacity: root.unlocked ? 1 : 0.4
                Text { anchors.centerIn: parent; text: "Restablecer curva"; color: Theme.dim; font.pixelSize: 11 * root.s }
                MouseArea {
                    enabled: root.unlocked
                    anchors.fill: parent
                    onClicked: { if (service) service.resetFanCurve(); }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 38 * root.s
            radius: root.cornerRadius
            color: service ? service.currentColor : Theme.accent
            opacity: service && service.applying ? 0.6 : 1
            Text {
                anchors.centerIn: parent
                text: service && service.applying ? "Aplicando..." : "Aplicar cambios"
                color: Theme.cardBot
                font.family: Theme.font
                font.pixelSize: 13 * root.s
            }
            MouseArea {
                anchors.fill: parent
                enabled: !(service && service.applying)
                onClicked: { if (service) service.applyAll(); }
            }
        }
    }
}
