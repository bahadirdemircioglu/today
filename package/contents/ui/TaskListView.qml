import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/ModelSync.js" as ModelSync

// Full list: view selector + subtitle, grouped rows, empty state, "+ New task" field, footer.
ColumnLayout {
    id: listRoot

    property var controller

    spacing: Kirigami.Units.smallSpacing

    property string shownViewKey: ""

    function isTaskIndex(i) {
        return i >= 0 && i < taskModel.count && taskModel.get(i).kind === "task";
    }

    // next task row from `from` in direction dir (+1/-1), skipping headers and pending rows
    function nextTaskIndex(from, dir) {
        for (var i = from + dir; i >= 0 && i < taskModel.count; i += dir) {
            if (isTaskIndex(i)) {
                return i;
            }
        }
        return isTaskIndex(from) ? from : -1;
    }

    function handleKey(event) {
        var row = listView.currentItem;
        var hasRow = row !== null && isTaskIndex(listView.currentIndex);
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_Up: {
            var next = nextTaskIndex(listView.currentIndex, event.key === Qt.Key_Down ? 1 : -1);
            if (next >= 0) {
                listView.currentIndex = next;
                listView.positionViewAtIndex(next, ListView.Contain);
            }
            return true;
        }
        case Qt.Key_Q:
        case Qt.Key_Slash:
            newTask.startAdding("");
            return true;
        case Qt.Key_Escape:
            listView.currentIndex = -1;
            listView.focus = false;
            return true;
        }
        if (!hasRow) {
            return false;
        }
        switch (event.key) {
        case Qt.Key_Space:
            row.startCompleting();
            return true;
        case Qt.Key_E:
        case Qt.Key_F2:
            row.startEditing();
            return true;
        case Qt.Key_T:
            duePicker.openFor(row);
            return true;
        case Qt.Key_M:
        case Qt.Key_Menu:
            taskMenu.openFor(row, row);
            return true;
        case Qt.Key_1:
        case Qt.Key_2:
        case Qt.Key_3:
        case Qt.Key_4:
            controller.setPriority(row.itemId, 5 - (event.key - Qt.Key_0));
            return true;
        case Qt.Key_Delete:
            controller.remove(row.itemId, row.title);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            Qt.openUrlExternally("https://app.todoist.com/app/task/" + row.itemId);
            return true;
        }
        return false;
    }

    function refresh() {
        if (!controller) {
            return;
        }
        // switching lists replaces the rows outright; only changes within a list animate
        if (controller.viewKey !== shownViewKey) {
            shownViewKey = controller.viewKey;
            taskModel.clear();
            ModelSync.sync(taskModel, controller.rows);
            listView.positionViewAtBeginning();
            return;
        }
        ModelSync.sync(taskModel, controller.rows);
    }

    ListModel {
        id: taskModel
    }

    TaskMenu {
        id: taskMenu
        controller: listRoot.controller
        onPickDateRequested: row => duePicker.openFor(row)
    }

    NewProjectDialog {
        id: newProjectDialog
        parent: listRoot
        controller: listRoot.controller
    }

    DuePicker {
        id: duePicker
        parent: listRoot
        controller: listRoot.controller
    }

    Connections {
        target: listRoot.controller
        function onRowsChanged() {
            listRoot.refresh();
        }
    }

    Component.onCompleted: refresh()

    readonly property string kind: controller ? controller.viewSpec.kind : "today"
    readonly property bool isFilterKind: kind === "filter" || kind === "query"
    readonly property string filterError: !controller ? ""
        : (kind === "filter" ? (controller.filterErrors[controller.viewSpec.id] || "")
           : (kind === "query" ? (controller.filterErrors["__query"] || "") : ""))
    readonly property string subtitle: {
        var c = controller;
        if (!c) {
            return "";
        }
        switch (kind) {
        case "today":
            return Qt.formatDate(new Date(c.nowMs), "dddd, d MMMM");
        case "upcoming":
            return "";
        case "filter":
        case "query":
            if (c.view.filterFetchedAt > 0 && (c.phase === "OFFLINE" || filterError !== "")) {
                return i18n("Results from %1", Qt.formatTime(new Date(c.view.filterFetchedAt), Qt.locale().timeFormat(Locale.ShortFormat)));
            }
            return c.count > 0 ? i18np("%1 task", "%1 tasks", c.count) : "";
        default:
            return c.count > 0 ? i18np("%1 task", "%1 tasks", c.count) : "";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ViewSelector {
                Layout.fillWidth: true
                controller: listRoot.controller
                onNewProjectRequested: newProjectDialog.openDialog()
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: listRoot.subtitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                opacity: 0.7
            }
        }

        GoalRing {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Kirigami.Units.gridUnit * 2
            progress: listRoot.kind === "today" && listRoot.controller ? listRoot.controller.goal : null
        }

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            visible: listRoot.controller.syncing
            running: visible
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: listRoot.controller.phase === "AUTH_INVALID"
        type: Kirigami.MessageType.Warning
        text: i18n("Todoist didn't accept your token.")
        actions: [
            Kirigami.Action {
                text: i18n("Reconnect")
                icon.name: "configure"
                onTriggered: Plasmoid.internalAction("configure").trigger()
            }
        ]
    }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        ListView {
            id: listView
            objectName: "taskList"

            model: taskModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: false

            delegate: TaskRow {
                id: taskRow
                width: ListView.view.width
                controller: listRoot.controller
                keyboardCurrent: ListView.isCurrentItem && listView.activeFocus
                onMenuRequested: anchor => taskMenu.openFor(taskRow, anchor)
                onAddRequested: dateKey => newTask.startAdding(dateKey)
                onSelectRequested: {
                    listView.currentIndex = index;
                    listView.forceActiveFocus();
                }
            }

            // Keyboard (Todoist-like): ↑/↓ move, Space complete, E/F2 edit, T date & time, M task menu, 1–4 priority,
            // Delete delete, Enter open in Todoist, Q or / new task, Esc leave the list.
            currentIndex: -1
            keyNavigationEnabled: false
            activeFocusOnTab: true
            onActiveFocusChanged: {
                if (activeFocus && !listRoot.isTaskIndex(currentIndex)) {
                    currentIndex = listRoot.nextTaskIndex(-1, 1);
                }
            }
            Keys.onPressed: event => {
                event.accepted = listRoot.handleKey(event);
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Kirigami.Units.longDuration }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: Kirigami.Units.longDuration }
                    NumberAnimation { property: "scale"; to: 0.9; duration: Kirigami.Units.longDuration }
                }
            }
            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
            }

            Kirigami.PlaceholderMessage {
                readonly property bool waitingForFilter: listRoot.isFilterKind && !listRoot.controller.view.hasFilterResult
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: listView.count === 0
                icon.name: listRoot.filterError === "client" ? "data-warning"
                         : (waitingForFilter ? "view-filter" : "checkmark")
                text: {
                    if (listRoot.filterError === "client") {
                        return i18n("Todoist couldn't run this filter");
                    }
                    if (waitingForFilter) {
                        return listRoot.controller.phase === "OFFLINE" ? i18n("Filter results need a connection")
                                                                        : i18n("Loading…");
                    }
                    return listRoot.kind === "today" ? i18n("All done for today") : i18n("No tasks here");
                }
                explanation: {
                    if (listRoot.filterError === "client") {
                        return i18n("Open it in Todoist to check the query.");
                    }
                    if (waitingForFilter) {
                        return "";
                    }
                    return listRoot.kind === "today" ? i18n("Enjoy the rest of your day.") : i18n("Add one below.");
                }
            }
        }
    }

    NewTaskField {
        id: newTask
        Layout.fillWidth: true
        onLeaveToList: {
            listView.currentIndex = listRoot.nextTaskIndex(taskModel.count, -1);
            listView.forceActiveFocus();
        }
        controller: listRoot.controller
    }

    StatusFooter {
        Layout.fillWidth: true
        controller: listRoot.controller
    }
}
