import QtQuick

Canvas {
    id: ring
    property color ringColor: "#8b8c90"
    property real strokeW: 3

    onRingColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var cx = width / 2, cy = height / 2;
        var r = Math.min(width, height) / 2 - strokeW / 2;
        ctx.lineWidth = strokeW;
        ctx.strokeStyle = ringColor;
        ctx.lineCap = "round";

        var gap = 0.55;
        var seg = (2 * Math.PI / 3);
        var start = -Math.PI / 2;
        for (var i = 0; i < 3; i++) {
            var a0 = start + i * seg + gap / 2;
            var a1 = start + (i + 1) * seg - gap / 2;
            ctx.beginPath();
            ctx.arc(cx, cy, r, a0, a1);
            ctx.stroke();
        }
    }
}
