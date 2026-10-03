import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/TaskStore.js" as TaskStore

// One task: round check + title + (time · project), optionally preceded by its section label.
// Roles come from TaskStore.flattenRows().
Item {
    id: row

    required property int index
    required property string key
    required property string kind
    required property string itemId
    required property string title
    required property string content
    required property string projectId
    required property int priority
    required property string projectName
    required property string dateKey
    required property int minutes
    required property bool isLate
    required property bool isRecurring
    required property string section
    required property string header

    property var controller

    readonly property bool pending: kind === "pending"
    property bool completing: false
    property bool editing: false

    // anchor: the ⋯ button, or null to open at the mouse position
    signal menuRequested(Item anchor)

    function startEditing() {
        if (pending) {
            return;
        }
        editing = true;
        editField.text = content;
        editField.forceActiveFocus();
        editField.selectAll();
    }

    function commitEdit() {
        if (!editing) {
            return;
        }
        if (editField.text.trim() !== content) {
            var err = controller.rename(itemId, editField.text);
            if (err === "too_long") {
                controller.showInfo(i18n("That's too long. Keep it under 1000 characters."), true);
                return;
            }
        }
        editing = false;
    }

    readonly property string whenText: {
        if (pending || !controller) {
            return "";
        }
        var time = controller.timeText(minutes);
        if (section === "overdue") {
            var date = controller.dateText(dateKey);
            return time ? date + " " + time : date;
        }
        return time;
    }
    readonly property string detailText: pending ? i18n("Waiting to sync") : projectName

    readonly property string headerText: {
        switch (header) {
        case "overdue":
            return i18n("Overdue");
        case "today":
            return i18n("Today");
        case "pending":
            return i18n("Waiting to sync");
        default:
            return "";
        }
    }

    implicitHeight: headerLabel.height + body.height
    height: implicitHeight

    function startCompleting() {
        if (completing || pending) {
            return;
        }
        completing = true;
        completeTimer.start();
    }

    PlasmaComponents3.Label {
        id: headerLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        height: row.headerText !== "" ? implicitHeight + Kirigami.Units.largeSpacing : 0
        visible: row.headerText !== ""
        verticalAlignment: Text.AlignBottom
        bottomPadding: Kirigami.Units.smallSpacing / 2
        text: row.headerText
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.weight: Font.DemiBold
        color: row.header === "overdue" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        opacity: 0.8
    }

    Item {
        id: body
        anchors.top: headerLabel.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: layout.implicitHeight + Kirigami.Units.smallSpacing * 2

        HoverHandler {
            id: rowHover
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: !row.pending && !row.editing
            onTapped: row.menuRequested(null)
        }

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: rowHover.hovered && !row.pending ? 0.12 : 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }

        RowLayout {
            id: layout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            RoundCheck {
                Layout.alignment: Qt.AlignVCenter
                priority: row.priority
                checked: row.completing
                enabled: !row.pending && !row.completing
                opacity: row.pending ? 0.4 : 1
                Accessible.name: i18n("Complete “%1”", row.title)
                onClicked: row.startCompleting()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.TextField {
                    id: editField
                    Layout.fillWidth: true
                    visible: row.editing
                    onAccepted: row.commitEdit()
                    Keys.onEscapePressed: row.editing = false
                    onActiveFocusChanged: {
                        if (!activeFocus) {
                            row.editing = false;
                        }
                    }
                }

                PlasmaComponents3.Label {
                    id: titleLabel
                    visible: !row.editing
                    Layout.fillWidth: true
                    text: row.title
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    font.strikeout: row.completing
                    opacity: row.completing || row.pending ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }

                    HoverHandler {
                        enabled: !row.pending
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: !row.pending
                        onTapped: {
                            if (TaskStore.isValidId(row.itemId)) {
                                Qt.openUrlExternally("https://app.todoist.com/app/task/" + row.itemId);
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: row.whenText !== "" || row.detailText !== ""
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        visible: row.whenText !== ""
                        text: row.whenText
                        textFormat: Text.PlainText
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: row.isLate || row.section === "overdue" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: row.isLate || row.section === "overdue" ? 1 : 0.7
                    }
                    Kirigami.Icon {
                        visible: row.isRecurring
                        implicitWidth: Kirigami.Units.iconSizes.small * 0.75
                        implicitHeight: implicitWidth
                        source: "view-refresh"
                        opacity: 0.6
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: row.detailText !== ""
                        text: row.detailText
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                }
            }

            PlasmaComponents3.ToolButton {
                id: moreButton
                Layout.alignment: Qt.AlignVCenter
                visible: !row.pending && !row.editing
                opacity: rowHover.hovered || activeFocus ? 1 : 0
                icon.name: "overflow-menu"
                text: i18n("More actions")
                display: PlasmaComponents3.AbstractButton.IconOnly
                onClicked: row.menuRequested(moreButton)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // let the check animation play before the row leaves the list
    Timer {
        id: completeTimer
        interval: Math.max(1, Kirigami.Units.longDuration * 2)
        onTriggered: row.controller.complete(row.itemId)
    }
}
