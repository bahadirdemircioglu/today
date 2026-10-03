import QtQuick
import QtQml

import org.kde.plasma.components as PlasmaComponents3

// Per-task context menu (right click or the row's ⋯ button), modelled on Todoist's task menu.
PlasmaComponents3.Menu {
    id: menu

    property var controller
    property Item row: null

    readonly property string itemId: row ? row.itemId : ""
    readonly property int priority: row ? row.priority : 1
    readonly property bool recurring: row ? row.isRecurring : false
    readonly property string projectId: row ? row.projectId : ""

    // anchor: an Item to open below (the ⋯ button), or null for the mouse position
    function openFor(r, anchor) {
        row = r;
        if (anchor) {
            popup(anchor, 0, anchor.height);
        } else {
            popup();
        }
    }

    PlasmaComponents3.MenuItem {
        text: i18n("Edit")
        icon.name: "document-edit"
        onTriggered: menu.row.startEditing()
    }

    PlasmaComponents3.MenuSeparator {}

    PlasmaComponents3.MenuItem {
        text: i18n("Today")
        icon.name: "go-jump-today"
        enabled: !menu.recurring
        onTriggered: menu.controller.reschedule(menu.itemId, "today")
    }
    PlasmaComponents3.MenuItem {
        text: i18n("Tomorrow")
        icon.name: "view-calendar-day"
        enabled: !menu.recurring
        onTriggered: menu.controller.reschedule(menu.itemId, "tomorrow")
    }
    PlasmaComponents3.MenuItem {
        text: i18n("This weekend")
        icon.name: "view-calendar-week"
        enabled: !menu.recurring
        onTriggered: menu.controller.reschedule(menu.itemId, "weekend")
    }
    PlasmaComponents3.MenuItem {
        text: i18n("Next week")
        icon.name: "view-calendar-upcoming-events"
        enabled: !menu.recurring
        onTriggered: menu.controller.reschedule(menu.itemId, "nextweek")
    }
    PlasmaComponents3.MenuItem {
        visible: menu.recurring
        height: visible ? implicitHeight : 0
        enabled: false
        text: i18n("Recurring: reschedule in Todoist")
    }

    PlasmaComponents3.MenuSeparator {}

    PlasmaComponents3.Menu {
        title: i18n("Priority")

        PlasmaComponents3.MenuItem {
            text: i18n("Priority 1")
            icon.name: "flag-red"
            checkable: true
            checked: menu.priority === 4
            onTriggered: menu.controller.setPriority(menu.itemId, 4)
        }
        PlasmaComponents3.MenuItem {
            text: i18n("Priority 2")
            icon.name: "flag-yellow"
            checkable: true
            checked: menu.priority === 3
            onTriggered: menu.controller.setPriority(menu.itemId, 3)
        }
        PlasmaComponents3.MenuItem {
            text: i18n("Priority 3")
            icon.name: "flag-blue"
            checkable: true
            checked: menu.priority === 2
            onTriggered: menu.controller.setPriority(menu.itemId, 2)
        }
        PlasmaComponents3.MenuItem {
            text: i18n("Priority 4")
            icon.name: "flag"
            checkable: true
            checked: menu.priority === 1
            onTriggered: menu.controller.setPriority(menu.itemId, 1)
        }
    }

    PlasmaComponents3.Menu {
        id: moveMenu
        title: i18n("Move to")

        Instantiator {
            model: menu.controller ? menu.controller.projects : []
            delegate: PlasmaComponents3.MenuItem {
                required property var modelData
                text: modelData.isInbox ? i18n("Inbox") : modelData.name
                icon.name: modelData.isInbox ? "mail-folder-inbox" : "folder"
                checkable: true
                checked: modelData.id === menu.projectId
                onTriggered: menu.controller.moveTo(menu.itemId, modelData.id)
            }
            onObjectAdded: (index, object) => moveMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => moveMenu.removeItem(object)
        }
    }

    PlasmaComponents3.MenuSeparator {}

    PlasmaComponents3.MenuItem {
        text: i18n("Copy link to task")
        icon.name: "edit-copy"
        onTriggered: menu.controller.copyLink(menu.itemId)
    }
    PlasmaComponents3.MenuItem {
        text: i18n("Open in Todoist")
        icon.name: "internet-services"
        onTriggered: Qt.openUrlExternally("https://app.todoist.com/app/task/" + menu.itemId)
    }

    PlasmaComponents3.MenuSeparator {}

    PlasmaComponents3.MenuItem {
        text: i18n("Delete")
        icon.name: "edit-delete"
        onTriggered: menu.controller.remove(menu.itemId, menu.row.title)
    }
}
