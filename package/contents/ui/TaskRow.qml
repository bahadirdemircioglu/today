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
    required property int childCount
    required property bool collapsed
    required property string labelsText
    required property string labelColors
    required property string projectColor
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
    // full description shown under the title
    property bool detailsOpen: false
    readonly property bool hasDetails: descriptionFull !== ""

    // anchor: the ⋯ button, or null to open at the mouse position
    signal menuRequested(Item anchor)
    // "+" on an Upcoming day header
    signal addRequested(string dateKey)
    // a click on the row (not on its controls): make it the keyboard-current row
    signal selectRequested()

    property bool keyboardCurrent: false

    readonly property string groupLabel: {
        switch (header) {
        case "overdue":
            return Lang.i18n("Overdue");
        case "today":
            return Lang.i18n("Today");
        case "pending":
            return Lang.i18n("Waiting to sync");
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
    // [{ name, color }] for the coloured label chips
    readonly property var labelList: {
        if (labelsText === "") {
            return [];
        }
        var names = labelsText.split(", ");
        var colors = labelColors.split(",");
        return names.map(function (n, i) { return { name: n, color: colors[i] || "" }; });
    }
    readonly property string detailText: {
        if (pending) {
            return Lang.i18n("Waiting to sync");
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
                controller.showInfo(Lang.i18n("That's too long. Keep it under 1000 characters."), true);
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
        height: row.groupLabel !== "" ? Math.max(headerLabel.implicitHeight, addButton.visible ? addButton.implicitHeight : 0,
                                                 rescheduleButton.visible ? rescheduleButton.implicitHeight : 0)
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
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            text: Lang.i18n("Add task to this day")
            display: PlasmaComponents3.AbstractButton.IconOnly
            onClicked: row.addRequested(row.headerDate)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        // "Reschedule" on the Overdue header: moves all overdue tasks at once (as on the web)
        PlasmaComponents3.ToolButton {
            id: rescheduleButton
            Layout.alignment: Qt.AlignBottom
            visible: row.header === "overdue" && !!row.controller
            text: Lang.i18n("Reschedule")
            icon.name: "view-calendar-day"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            topPadding: 0
            bottomPadding: 0
            Accessible.name: Lang.i18n("Reschedule all overdue tasks")
            onClicked: rescheduleMenu.popup(rescheduleButton, 0, rescheduleButton.height)
            PlasmaComponents3.ToolTip.text: Accessible.name
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

            PlasmaComponents3.Menu {
                id: rescheduleMenu
                PlasmaComponents3.MenuItem {
                    text: Lang.i18n("Today")
                    icon.name: "go-jump-today"
                    onTriggered: row.controller.rescheduleOverdue("today")
                }
                PlasmaComponents3.MenuItem {
                    text: Lang.i18n("Tomorrow")
                    icon.name: "view-calendar-day"
                    onTriggered: row.controller.rescheduleOverdue("tomorrow")
                }
                PlasmaComponents3.MenuItem {
                    text: Lang.i18n("This weekend")
                    icon.name: "view-calendar-week"
                    onTriggered: row.controller.rescheduleOverdue("weekend")
                }
                PlasmaComponents3.MenuItem {
                    text: Lang.i18n("Next week")
                    icon.name: "view-calendar-upcoming-events"
                    onTriggered: row.controller.rescheduleOverdue("nextweek")
                }
            }
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
        TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: !row.pending && !row.editing
            onTapped: row.selectRequested()
        }

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: row.keyboardCurrent ? 0.22 : (rowHover.hovered && !row.pending ? 0.12 : 0)
            border.width: row.keyboardCurrent ? 1 : 0
            border.color: Kirigami.Theme.highlightColor
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

            PlasmaComponents3.ToolButton {
                Layout.alignment: Qt.AlignVCenter
                visible: row.childCount > 0
                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                icon.name: row.collapsed ? "arrow-right" : "arrow-down"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                text: row.collapsed ? Lang.i18np("Show %1 sub-task", "Show %1 sub-tasks", row.childCount)
                                    : Lang.i18n("Hide sub-tasks")
                display: PlasmaComponents3.AbstractButton.IconOnly
                onClicked: row.controller.toggleCollapsed(row.itemId)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            RoundCheck {
                Layout.alignment: Qt.AlignVCenter
                priority: row.priority
                checked: row.completing
                enabled: !row.pending && !row.completing
                opacity: row.pending ? 0.4 : 1
                Accessible.name: Lang.i18n("Complete “%1”", row.title)
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
                    visible: row.hasDetails && !row.editing
                    text: row.detailsOpen ? row.descriptionFull : row.description
                    textFormat: Text.PlainText
                    wrapMode: row.detailsOpen ? Text.Wrap : Text.NoWrap
                    elide: row.detailsOpen ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: row.detailsOpen ? 40 : 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: row.detailsOpen ? 0.85 : 0.6

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: row.detailsOpen = !row.detailsOpen
                    }
                }
                PlasmaComponents3.Label {
                    visible: row.collapsed
                    text: Lang.i18np("%1 sub-task", "%1 sub-tasks", row.childCount)
                    textFormat: Text.PlainText
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
                        text: row.controller && row.deadlineKey ? Lang.i18nc("deadline date", "Deadline %1", row.controller.dateText(row.deadlineKey)) : ""
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
                        visible: row.pending
                        text: Lang.i18n("Waiting to sync")
                        textFormat: Text.PlainText
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                    // project like on the web: a "#" in the project's Todoist colour
                    PlasmaComponents3.Label {
                        visible: !row.pending && row.projectName !== ""
                        text: "#"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.Bold
                        color: row.projectColor !== "" ? row.projectColor : Kirigami.Theme.textColor
                        opacity: row.projectColor !== "" ? 1 : 0.7
                    }
                    PlasmaComponents3.Label {
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 9
                        visible: !row.pending && row.projectName !== ""
                        text: row.projectName
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                    Repeater {
                        model: row.pending ? [] : row.labelList
                        delegate: PlasmaComponents3.Label {
                            required property var modelData
                            text: "@" + modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: modelData.color !== "" ? modelData.color : Kirigami.Theme.textColor
                            opacity: modelData.color !== "" ? 1 : 0.7
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }

            PlasmaComponents3.ToolButton {
                id: moreButton
                Layout.alignment: Qt.AlignVCenter
                visible: !row.pending && !row.editing
                opacity: rowHover.hovered || activeFocus || row.keyboardCurrent ? 1 : 0
                icon.name: "overflow-menu"
                text: Lang.i18n("More actions")
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
