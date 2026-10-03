import QtQuick

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// Panel: icon + count badge; click toggles the popup.
MouseArea {
    id: compactRoot

    property PlasmoidItem plasmoidItem
    property var controller

    readonly property int count: controller ? controller.badgeCount : 0
    readonly property bool needsAttention: !!controller
        && (controller.phase === "SETUP" || controller.phase === "AUTH_INVALID")
    readonly property bool hasOverdue: !!controller && controller.badgeAlert
    property bool wasExpanded: false

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: wasExpanded = plasmoidItem.expanded
    onClicked: plasmoidItem.expanded = !wasExpanded

    Accessible.name: plasmoidItem ? plasmoidItem.toolTipMainText : ""
    Accessible.description: plasmoidItem ? plasmoidItem.toolTipSubText : ""
    Accessible.role: Accessible.Button

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: Plasmoid.icon
        active: compactRoot.containsMouse
    }

    Rectangle {
        id: badge
        readonly property int side: Math.max(Kirigami.Units.iconSizes.small * 0.75,
                                             Math.round(Math.min(compactRoot.width, compactRoot.height) * 0.45))
        visible: !compactRoot.needsAttention && compactRoot.count > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: side
        width: Math.max(side, badgeLabel.implicitWidth + side * 0.4)
        radius: height / 2
        color: compactRoot.hasOverdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: compactRoot.count > 99 ? "99+" : compactRoot.count
            textFormat: Text.PlainText
            color: Kirigami.Theme.highlightedTextColor
            font.pixelSize: Math.round(badge.height * 0.7)
            font.weight: Font.DemiBold
        }
    }

    Kirigami.Icon {
        visible: compactRoot.needsAttention
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.round(parent.width * 0.5)
        height: width
        source: "emblem-warning"
    }
}
