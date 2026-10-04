import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// "+ New task" row: text goes to Todoist Quick Add (natural language, #project, @label, p1).
// The current view decides where it lands (see ContextRules.js); "+" on an Upcoming day sets addDate.
ColumnLayout {
    id: field

    property var controller
    property string addDate: ""

    signal leaveToList()

    spacing: Kirigami.Units.smallSpacing / 2

    property int seenFocusRequest: 0

    function takeFocusRequest() {
        if (!controller || controller.focusNewTaskRequest === seenFocusRequest) {
            return;
        }
        seenFocusRequest = controller.focusNewTaskRequest;
        // the popup may just be opening: ignore stale requests
        if (Date.now() - controller.focusNewTaskAt < 3000) {
            Qt.callLater(input.forceActiveFocus);
        }
    }

    Connections {
        target: field.controller
        function onFocusNewTaskRequestChanged() {
            field.takeFocusRequest();
        }
    }

    Component.onCompleted: takeFocusRequest()

    function startAdding(dateKey) {
        addDate = dateKey || "";
        input.forceActiveFocus();
    }

    function submit() {
        var err = controller.addTask(input.text, addDate);
        if (err === "") {
            input.text = "";
            addDate = "";
        } else if (err === "too_long") {
            controller.showInfo(Lang.i18n("That's too long. Keep it under 1000 characters."), true);
        }
    }

    readonly property string placeholder: {
        if (!controller) {
            return "";
        }
        switch (controller.viewSpec.kind) {
        case "project":
            return Lang.i18n("New task in %1", controller.viewTitle);
        case "inbox":
            return Lang.i18n("New task in Inbox");
        case "label":
            return Lang.i18n("New task with @%1", controller.viewTitle);
        default:
            return Lang.i18n("New task, e.g. “Dentist tomorrow 3pm #Personal”");
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: field.addDate !== ""
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: field.controller && field.addDate ? Lang.i18n("Adding to %1", field.controller.dateText(field.addDate)) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.8
        }
        PlasmaComponents3.ToolButton {
            icon.name: "edit-clear"
            text: Lang.i18n("Don't set a date")
            display: PlasmaComponents3.AbstractButton.IconOnly
            onClicked: field.addDate = ""
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: field.placeholder
            onAccepted: field.submit()
            Keys.onEscapePressed: {
                text = "";
                field.addDate = "";
            }
            // ↑ from an empty field moves into the list
            Keys.onUpPressed: event => {
                event.accepted = text === "";
                if (event.accepted) {
                    field.leaveToList();
                }
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "list-add"
            text: Lang.i18n("Add task")
            display: PlasmaComponents3.AbstractButton.IconOnly
            enabled: input.text.trim() !== ""
            onClicked: field.submit()
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }
}
