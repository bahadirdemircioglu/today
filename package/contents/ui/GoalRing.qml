import QtQuick
import QtQuick.Shapes

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Daily goal progress ring (like Todoist's productivity widget): "3" inside, 3/5 of the circle drawn.
Item {
    id: ring

    property var progress: null      // Goals.progress() result
    property real thickness: Math.max(2, Math.round(width / 10))

    readonly property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.15)
    readonly property color fillColor: progress && progress.reached ? Kirigami.Theme.positiveTextColor
                                                                    : Kirigami.Theme.highlightColor

    implicitWidth: Kirigami.Units.gridUnit * 2
    implicitHeight: implicitWidth
    visible: progress !== null

    Accessible.role: Accessible.ProgressBar
    Accessible.name: progress ? i18n("%1 of %2 tasks done today", progress.completed, progress.goal) : ""

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            fillColor: "transparent"
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (ring.width - ring.thickness) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: ring.fillColor
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (ring.width - ring.thickness) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: ring.progress ? 360 * ring.progress.fraction : 0
                Behavior on sweepAngle { NumberAnimation { duration: Kirigami.Units.longDuration } }
            }
        }
    }

    PlasmaComponents3.Label {
        anchors.centerIn: parent
        text: ring.progress ? ring.progress.completed : ""
        textFormat: Text.PlainText
        font.pixelSize: Math.round(ring.height * 0.38)
        font.weight: Font.DemiBold
    }

    HoverHandler {
        id: ringHover
    }
    PlasmaComponents3.ToolTip {
        visible: ringHover.hovered && ring.progress !== null
        text: ring.progress ? (ring.progress.reached ? i18n("Daily goal reached: %1 of %2 tasks", ring.progress.completed, ring.progress.goal)
                                                    : i18n("%1 of %2 tasks done today", ring.progress.completed, ring.progress.goal))
                            : ""
    }
}
