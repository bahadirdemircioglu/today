import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// "+ New task" row: text goes to Todoist Quick Add (natural language, #project, @label, p1).
RowLayout {
    id: field

    property var controller

    spacing: Kirigami.Units.smallSpacing

    function submit() {
        var err = controller.addTask(input.text);
        if (err === "") {
            input.text = "";
        } else if (err === "too_long") {
            controller.showInfo(i18n("That's too long. Keep it under 1000 characters."), true);
        }
    }

    PlasmaComponents3.TextField {
        id: input
        Layout.fillWidth: true
        placeholderText: i18n("New task, e.g. “Dentist tomorrow 3pm #Personal”")
        onAccepted: field.submit()
        Keys.onEscapePressed: text = ""
    }

    PlasmaComponents3.ToolButton {
        icon.name: "list-add"
        text: i18n("Add task")
        display: PlasmaComponents3.AbstractButton.IconOnly
        enabled: input.text.trim() !== ""
        onClicked: field.submit()
        PlasmaComponents3.ToolTip.text: text
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
