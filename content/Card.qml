pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.PluginKit.Singletons

Item {
    id: root
    property var pluginApi
    property var screen
    property bool active: false
    property string density: "compact"
    property real s: 1
    property real widthBudget: 0

    implicitWidth: 80 * root.s
    implicitHeight: 24 * root.s

    Text {
        anchors.centerIn: parent
        text: "Legion Power"
        color: Theme.dim
        font.pixelSize: 11 * root.s
    }
}
