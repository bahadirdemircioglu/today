import QtQuick
import QtQuick.Layouts
import QtQml

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// The list's title doubles as the view switcher: "Today ▾" → Inbox / Today / Upcoming,
// Projects ▸, Labels ▸, Filters ▸, and "Start here in this widget" (pins the view).
PlasmaComponents3.AbstractButton {
    id: selector

    property var controller

    readonly property var projectEntries: controller ? controller.nav.filter(function (e) { return e.kind === "project"; }) : []
    readonly property var labelEntries: controller ? controller.nav.filter(function (e) { return e.kind === "label"; }) : []
    readonly property var filterEntries: controller ? controller.nav.filter(function (e) { return e.kind === "filter"; }) : []

    function countOf(key) {
        var nav = controller ? controller.nav : [];
        for (var i = 0; i < nav.length; i++) {
            if (nav[i].key === key) {
                return nav[i].count;
            }
        }
        return -1;
    }

    function entryText(name, count, depth) {
        var indent = "";
        for (var i = 0; i < depth; i++) {
            indent += "    ";
        }
        return count > 0 ? i18nc("view name with task count", "%1%2 (%3)", indent, name, count) : indent + name;
    }

    hoverEnabled: true
    padding: 0
    text: controller ? controller.viewTitle : ""
    Accessible.name: i18n("Switch list: %1", text)
    onClicked: navMenu.popup(selector, 0, selector.height)

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            Layout.maximumWidth: implicitWidth
            level: 1
            text: selector.text
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Kirigami.Icon {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            source: "arrow-down"
            opacity: selector.hovered || navMenu.opened ? 1 : 0.6
        }
    }

    PlasmaComponents3.Menu {
        id: navMenu

        PlasmaComponents3.MenuItem {
            text: selector.entryText(i18n("Inbox"), selector.countOf("inbox"), 0)
            icon.name: "mail-folder-inbox"
            checkable: true
            checked: selector.controller && selector.controller.viewKey === "inbox"
            onTriggered: selector.controller.setView("inbox")
        }
        PlasmaComponents3.MenuItem {
            text: selector.entryText(i18n("Today"), selector.countOf("today"), 0)
            icon.name: "go-jump-today"
            checkable: true
            checked: selector.controller && selector.controller.viewKey === "today"
            onTriggered: selector.controller.setView("today")
        }
        PlasmaComponents3.MenuItem {
            text: selector.entryText(i18n("Upcoming"), selector.countOf("upcoming"), 0)
            icon.name: "view-calendar-upcoming-events"
            checkable: true
            checked: selector.controller && selector.controller.viewKey === "upcoming"
            onTriggered: selector.controller.setView("upcoming")
        }

        PlasmaComponents3.MenuSeparator {}

        PlasmaComponents3.Menu {
            id: projectsMenu
            title: i18n("Projects")
            enabled: selector.projectEntries.length > 0

            Instantiator {
                model: selector.projectEntries
                delegate: PlasmaComponents3.MenuItem {
                    required property var modelData
                    text: selector.entryText(modelData.name, modelData.count, modelData.depth)
                    checkable: true
                    checked: selector.controller.viewKey === modelData.key
                    onTriggered: selector.controller.setView(modelData.key)
                }
                onObjectAdded: (index, object) => projectsMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => projectsMenu.removeItem(object)
            }
        }
        PlasmaComponents3.Menu {
            id: labelsMenu
            title: i18n("Labels")
            enabled: selector.labelEntries.length > 0

            Instantiator {
                model: selector.labelEntries
                delegate: PlasmaComponents3.MenuItem {
                    required property var modelData
                    text: selector.entryText("@" + modelData.name, modelData.count, 0)
                    checkable: true
                    checked: selector.controller.viewKey === modelData.key
                    onTriggered: selector.controller.setView(modelData.key)
                }
                onObjectAdded: (index, object) => labelsMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => labelsMenu.removeItem(object)
            }
        }
        PlasmaComponents3.Menu {
            id: filtersMenu
            title: i18n("Filters")
            enabled: selector.filterEntries.length > 0

            Instantiator {
                model: selector.filterEntries
                delegate: PlasmaComponents3.MenuItem {
                    required property var modelData
                    text: selector.entryText(modelData.name, modelData.count, 0)
                    checkable: true
                    checked: selector.controller.viewKey === modelData.key
                    onTriggered: selector.controller.setView(modelData.key)
                }
                onObjectAdded: (index, object) => filtersMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => filtersMenu.removeItem(object)
            }
        }

        PlasmaComponents3.MenuSeparator {}

        PlasmaComponents3.MenuItem {
            text: i18n("Start here in this widget")
            icon.name: "window-pin"
            checkable: true
            checked: selector.controller && Plasmoid.configuration.pinnedView === selector.controller.viewKey
            onTriggered: Plasmoid.configuration.pinnedView = checked ? selector.controller.viewKey : ""
        }
    }
}
