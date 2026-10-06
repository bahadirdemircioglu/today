import QtQuick
import QtQuick.Templates as T

import org.kde.kirigami as Kirigami

import "logic/Colors.js" as Colors

// Round, priority-coloured completion button with a fill + check animation.
// Todoist API priority: 4 = p1 (highest) ... 1 = p4.
T.AbstractButton {
    id: control

    property int priority: 1
    // Todoist's red/orange/blue instead of the Plasma theme's colours
    property bool todoistColors: false

    readonly property color ringColor: {
        if (todoistColors && Colors.priorityHex(priority) !== "") {
            return Colors.priorityHex(priority);
        }
        switch (priority) {
        case 4:
            return Kirigami.Theme.negativeTextColor;
        case 3:
            return Kirigami.Theme.neutralTextColor;
        case 2:
            return Kirigami.Theme.linkColor;
        default:
            return Kirigami.Theme.disabledTextColor;
        }
    }

    implicitWidth: Kirigami.Units.iconSizes.smallMedium
    implicitHeight: Kirigami.Units.iconSizes.smallMedium
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked

    background: Rectangle {
        radius: width / 2
        border.width: 2
        border.color: control.ringColor
        color: control.checked ? control.ringColor
             : (control.hovered || control.visualFocus
                ? Qt.rgba(control.ringColor.r, control.ringColor.g, control.ringColor.b, 0.15)
                : "transparent")
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }

    contentItem: Item {
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.7)
            height: width
            source: "checkmark"
            isMask: true
            color: control.checked ? Kirigami.Theme.highlightedTextColor : control.ringColor
            scale: control.checked ? 1 : (control.hovered ? 0.8 : 0.4)
            opacity: control.checked ? 1 : (control.hovered ? 0.6 : 0)
            Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutBack } }
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }
    }
}
