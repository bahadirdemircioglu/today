import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/TaskStore.js" as TaskStore

// One list row: an optional group label (Overdue / section / day …) above a task with its round
// check, title, date · project · labels and the first line of its description. Rows of kind
// "header" are an empty day in Upcoming: only the label (with its "+") is drawn.
// Roles come from ViewModel.flattenView().
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
    required property bool isOverdue
    required property bool showDate
    required property int depth
    required property string labelsText
    required property string description
    required property string descriptionFull
    required property string deadlineKey
    required property bool deadlineDue
    required property string section
    required property string header
    required property string headerText
    required property string headerDate

    property var controller

    readonly property bool pending: kind === "pending"
    readonly property bool headerOnly: kind === "header"
    property bool completing: false
    property bool editing: false

    // anchor: the ⋯ button, or null to open at the mouse position
    signal menuRequested(Item anchor)
    // "+" on an Upcoming day header
    signal addRequested(string dateKey)

    readonly property string groupLabel: {
        switch (header) {
        case "overdue":
            return i18n("Overdue");
        case "today":
            return i18n("Today");
        case "pending":
            return i18n("Waiting to sync");
        case "section":
            return headerText;
        case "day":
            return controller ? controller.dayHeaderText(headerDate) : headerDate;
        default:
            return "";
        }
    }

    readonly property bool redDate: isLate || isOverdue || section === "overdue"
    readonly property string whenText: {
        if (pending || headerOnly || !controller) {
            return "";
        }
        var time = controller.timeText(minutes);
        if ((section === "overdue" || showDate) && dateKey !== "") {
            var date = controller.dateText(dateKey);
            return time ? date + " " + time : date;
        }
        return time;
    }
    readonly property string labelsDisplay: labelsText === "" ? ""
        : labelsText.split(", ").map(function (l) { return "@" + l; }).join(" ")
    readonly property string detailText: {
        if (pending) {
            return i18n("Waiting to sync");
        }
        var parts = [];
        if (projectName !== "") {
            parts.push(projectName);
        }
        if (labelsDisplay !== "") {
            parts.push(labelsDisplay);
        }
        return parts.join(" · ");
    }

    implicitHeight: headerRow.height + (headerOnly ? 0 : body.height)
    height: implicitHeight

    function startCompleting() {
        if (completing || pending || headerOnly) {
            return;
        }
        completing = true;
        completeTimer.start();
    }

    function startEditing() {
        if (pending || headerOnly) {
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

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        height: row.groupLabel !== "" ? Math.max(headerLabel.implicitHeight, addButton.visible ? addButton.implicitHeight : 0)
                                        + Kirigami.Units.largeSpacing : 0
        visible: row.groupLabel !== ""
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            id: headerLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            bottomPadding: Kirigami.Units.smallSpacing / 2
            text: row.groupLabel
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.weight: Font.DemiBold
            color: row.header === "overdue" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            opacity: 0.8
        }
        PlasmaComponents3.ToolButton {
            id: addButton
            Layout.alignment: Qt.AlignBottom
            visible: row.header === "day"
            icon.name: "list-add"
            text: i18n("Add task to this day")
            display: PlasmaComponents3.AbstractButton.IconOnly
            onClicked: row.addRequested(row.headerDate)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    Item {
        id: body
        visible: !row.headerOnly
        anchors.top: headerRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: row.depth * Kirigami.Units.gridUnit
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

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: row.description !== "" && !row.editing
                    text: row.description
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: row.whenText !== "" || row.detailText !== "" || row.deadlineKey !== ""
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        visible: row.whenText !== ""
                        text: row.whenText
                        textFormat: Text.PlainText
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: row.redDate ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: row.redDate ? 1 : 0.7
                    }
                    Kirigami.Icon {
                        visible: row.deadlineKey !== ""
                        implicitWidth: Kirigami.Units.iconSizes.small * 0.75
                        implicitHeight: implicitWidth
                        source: "flag"
                        color: row.deadlineDue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        isMask: true
                        opacity: row.deadlineDue ? 1 : 0.6
                    }
                    PlasmaComponents3.Label {
                        visible: row.deadlineKey !== ""
                        text: row.controller && row.deadlineKey ? i18nc("deadline date", "Deadline %1", row.controller.dateText(row.deadlineKey)) : ""
                        textFormat: Text.PlainText
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: row.deadlineDue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: row.deadlineDue ? 1 : 0.7
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
        onTriggered: row.controller.complete(row.itemId, row.title)
    }
}
