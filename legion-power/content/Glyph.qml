pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.PluginKit.Singletons

Item {
    id: root

    property var pluginApi
    property var screen
    property bool active: false
    property string density: "glyph"
    property real s: 1
    property real widthBudget: 0

    readonly property var service: pluginApi ? pluginApi.mainInstance : null

    implicitWidth: 20 * root.s
    implicitHeight: 20 * root.s

    NotchedRing {
        anchors.centerIn: parent
        width: 16 * root.s
        height: 16 * root.s
        strokeW: 3 * root.s
        ringColor: root.service ? root.service.currentColor : "#B96FE0"
        Behavior on ringColor { ColorAnimation { duration: 200 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (root.pluginApi) root.pluginApi.togglePanel(); }
    }
}
