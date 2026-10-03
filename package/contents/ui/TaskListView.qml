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

            model: taskModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: false

            delegate: TaskRow {
                id: taskRow
                width: ListView.view.width
                controller: listRoot.controller
                onMenuRequested: anchor => taskMenu.openFor(taskRow, anchor)
                onAddRequested: dateKey => newTask.startAdding(dateKey)
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
        controller: listRoot.controller
    }

    StatusFooter {
        Layout.fillWidth: true
        controller: listRoot.controller
    }
}
