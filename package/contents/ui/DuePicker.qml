import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/DateUtil.js" as DateUtil

// "Pick date & time…": quick choices, a month calendar, an optional time, or a schedule typed in
// Todoist's own words ("next friday 3pm", "every monday 9am"). Recurring tasks only get the typed
// schedule, because sending a plain date would drop their recurrence.
QQC2.Popup {
    id: picker

    property var controller
    property string itemId: ""
    property string taskTitle: ""
    property bool recurring: false

    property string selectedKey: ""
    property bool noDate: false
    property int shownYear: 2026
    property int shownMonth: 0       // 0-based, as in JS Date / MonthGrid
    property string error: ""

    function openFor(row) {
        itemId = row.itemId;
        taskTitle = row.title;
        recurring = row.isRecurring;
        noDate = false;
        error = "";
        selectedKey = row.dateKey || "";
        timeField.text = DateUtil.minutesToHHMM(row.minutes);
        scheduleField.text = "";
        var p = DateUtil.splitDateKey(selectedKey || controller.view.todayKey);
        if (p) {
            shownYear = p.y;
            shownMonth = p.m - 1;
        }
        open();
        (recurring ? scheduleField : timeField).forceActiveFocus();
    }

    function pick(key) {
        selectedKey = key;
        noDate = false;
        error = "";
    }

    function shiftMonth(delta) {
        var m = shownMonth + delta;
        shownYear += Math.floor(m / 12);
        shownMonth = ((m % 12) + 12) % 12;
    }

    function save() {
        var typed = scheduleField.text.trim();
        if (typed !== "") {
            controller.setDue(itemId, { string: typed });
            close();
            return;
        }
        if (recurring) {
            error = i18n("Type a new schedule for this recurring task.");
            return;
        }
        if (noDate) {
            controller.setDue(itemId, null);
            close();
            return;
        }
        if (!selectedKey) {
            error = i18n("Pick a day first.");
            return;
        }
        var due = DateUtil.composeDue(selectedKey, timeField.text);
        if (!due) {
            error = i18n("That time isn't valid. Use e.g. 15:30.");
            return;
        }
        controller.setDue(itemId, due);
        close();
    }

    modal: true
    focus: true
    anchors.centerIn: QQC2.Overlay.overlay
    width: Math.min(Kirigami.Units.gridUnit * 19, parent ? parent.width - Kirigami.Units.gridUnit : Kirigami.Units.gridUnit * 19)
    padding: Kirigami.Units.largeSpacing

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 4
            text: picker.taskTitle
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        // quick choices
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            enabled: !picker.recurring

            Repeater {
                model: [
                    { which: "today", label: i18n("Today") },
                    { which: "tomorrow", label: i18n("Tomorrow") },
                    { which: "weekend", label: i18n("This weekend") },
                    { which: "nextweek", label: i18n("Next week") }
                ]
                delegate: PlasmaComponents3.Button {
                    required property var modelData
                    readonly property string key: DateUtil.quickDate(picker.controller.view.todayKey, modelData.which)
                    text: modelData.label
                    checkable: true
                    checked: !picker.noDate && picker.selectedKey === key
                    onClicked: {
                        picker.pick(key);
                        var p = DateUtil.splitDateKey(key);
                        picker.shownYear = p.y;
                        picker.shownMonth = p.m - 1;
                    }
                }
            }
            PlasmaComponents3.Button {
                text: i18n("No date")
                icon.name: "edit-clear"
                checkable: true
                checked: picker.noDate
                onClicked: {
                    picker.noDate = true;
                    picker.selectedKey = "";
                }
            }
        }

        // month calendar
        ColumnLayout {
            Layout.fillWidth: true
            enabled: !picker.recurring
            opacity: enabled ? 1 : 0.4
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.ToolButton {
                    icon.name: "go-previous"
                    text: i18n("Previous month")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: picker.shiftMonth(-1)
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(picker.shownYear, picker.shownMonth, 1), "MMMM yyyy")
                    font.weight: Font.DemiBold
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "go-next"
                    text: i18n("Next month")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: picker.shiftMonth(1)
                }
            }

            QQC2.DayOfWeekRow {
                Layout.fillWidth: true
                locale: Qt.locale()
                delegate: PlasmaComponents3.Label {
                    required property string shortName
                    text: shortName
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                }
            }

            QQC2.MonthGrid {
                id: grid
                Layout.fillWidth: true
                // MonthGrid sizes its cells from its own height, so it needs an explicit one in a layout
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.7 * 6
                month: picker.shownMonth
                year: picker.shownYear
                locale: Qt.locale()
                delegate: Item {
                    id: cell
                    required property var model
                    readonly property string key: DateUtil.keyOfLocalDate(model.date)
                    readonly property bool selected: !picker.noDate && key === picker.selectedKey
                    readonly property bool past: key < picker.controller.view.todayKey

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2
                        height: width
                        radius: width / 2
                        color: cell.selected ? Kirigami.Theme.highlightColor : "transparent"
                        border.width: cell.key === picker.controller.view.todayKey && !cell.selected ? 1 : 0
                        border.color: Kirigami.Theme.highlightColor
                    }
                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        text: cell.model.day
                        color: cell.selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        opacity: cell.model.month === picker.shownMonth ? (cell.past ? 0.45 : 1) : 0.3
                    }
                }
                onClicked: date => picker.pick(DateUtil.keyOfLocalDate(date))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            enabled: !picker.recurring && !picker.noDate
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Time:")
            }
            PlasmaComponents3.TextField {
                id: timeField
                Layout.fillWidth: true
                placeholderText: i18n("optional, e.g. 15:30")
                inputMethodHints: Qt.ImhPreferNumbers
                onAccepted: picker.save()
                onTextEdited: picker.error = ""
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: picker.recurring ? i18n("Recurring task: type its new schedule")
                                   : i18n("…or type it the Todoist way")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }
        PlasmaComponents3.TextField {
            id: scheduleField
            Layout.fillWidth: true
            placeholderText: i18n("e.g. next friday 3pm, every monday 9am")
            onAccepted: picker.save()
            onTextEdited: picker.error = ""
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: picker.error !== ""
            text: picker.error
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Button {
                text: i18n("Cancel")
                onClicked: picker.close()
            }
            PlasmaComponents3.Button {
                text: i18n("Save")
                icon.name: "dialog-ok-apply"
                onClicked: picker.save()
            }
        }
    }
}
