import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/ModelSync.js" as ModelSync

// Full list: header, Overdue/Today sections, empty state, "+ New task" field, footer.
ColumnLayout {
    id: listRoot

    property var controller

    spacing: Kirigami.Units.smallSpacing

    function refresh() {
        if (controller) {
            ModelSync.sync(taskModel, controller.rows);
        }
    }

    ListModel {
        id: taskModel
    }

    Connections {
        target: listRoot.controller
        function onRowsChanged() {
            listRoot.refresh();
        }
    }

    Component.onCompleted: refresh()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 1
                text: i18n("Today")
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: Qt.formatDate(new Date(listRoot.controller.nowMs), "dddd, d MMMM")
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
                width: ListView.view.width
                controller: listRoot.controller
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
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: listView.count === 0
                icon.name: "checkmark"
                text: i18n("All done for today")
                explanation: i18n("Enjoy the rest of your day.")
            }
        }
    }

    NewTaskField {
        Layout.fillWidth: true
        controller: listRoot.controller
    }

    StatusFooter {
        Layout.fillWidth: true
        controller: listRoot.controller
    }
}
