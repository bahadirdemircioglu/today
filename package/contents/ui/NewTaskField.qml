import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/QuickParse.js" as QuickParse

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
            Qt.callLater(input.forceInputFocus);
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
        input.forceInputFocus();
    }

    function submit() {
        var text = input.text;
        var date = addDate;
        var spans = [];
        if (input.typedDate) {
            spans = spans.concat(input.typedDate.spans);
            date = QuickParse.dueValue(input.typedDate);
        }
        // a known project is applied by id: works for names with spaces or in any language
        var projectId = "";
        var p = input.typedProject;
        if (p && p.id && QuickParse.stripSpans(input.text, spans.concat([[p.start, p.end]])) !== "") {
            spans.push([p.start, p.end]);
            projectId = p.id;
        }
        if (spans.length) {
            text = QuickParse.stripSpans(input.text, spans);
        }
        var err = controller.addTask(text, date, projectId);
        if (err === "") {
            input.reset();
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

    QuickTextField {
        id: input
        Layout.fillWidth: true
        controller: field.controller
        inputObjectName: "newTaskInput"
        placeholderText: field.placeholder
        buttonText: Lang.i18n("Add task")
        onSubmitted: field.submit()
        onCancelled: {
            input.reset();
            field.addDate = "";
        }
        onUpFromEmpty: field.leaveToList()
    }
}
