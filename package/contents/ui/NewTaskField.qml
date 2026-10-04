import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/QuickParse.js" as QuickParse
import "logic/Colors.js" as Colors

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

    // live reading of the text (see QuickParse.js); a recognised date is sent separately
    readonly property var parsed: controller && input.text.trim() !== "" ? controller.parseQuickAdd(input.text) : null
    // the user clicked the date chip: keep the words as typed
    property bool keepDateText: false
    readonly property var typedDate: parsed && parsed.date && !keepDateText
                                     && QuickParse.stripSpans(input.text, parsed.date.spans) !== "" ? parsed.date : null

    function submit() {
        var text = input.text;
        var date = addDate;
        if (typedDate) {
            text = QuickParse.stripSpans(input.text, typedDate.spans);
            date = QuickParse.dueValue(typedDate);
        }
        var err = controller.addTask(text, date);
        if (err === "") {
            input.text = "";
            addDate = "";
            keepDateText = false;
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
            objectName: "newTaskInput"
            Layout.fillWidth: true
            placeholderText: field.placeholder
            onAccepted: field.submit()
            Keys.onEscapePressed: {
                text = "";
                field.addDate = "";
                field.keepDateText = false;
            }
            onTextChanged: {
                if (text === "") {
                    field.keepDateText = false;
                }
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

    // Live preview: date, project, labels and priority as Todoist will read them
    Flow {
        id: preview
        Layout.fillWidth: true
        visible: !!field.parsed && (!!field.parsed.date || field.parsed.recurring || !!field.parsed.project
                                    || field.parsed.labels.length > 0 || field.parsed.priority > 0)
        spacing: Kirigami.Units.largeSpacing

        // a read-only tag: optional icon + coloured text
        component Tag: RowLayout {
            property string iconName: ""
            property string text: ""
            property color tint: Kirigami.Theme.textColor
            spacing: Kirigami.Units.smallSpacing / 2
            Kirigami.Icon {
                visible: parent.iconName !== ""
                source: parent.iconName
                color: parent.tint
                isMask: true
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents3.Label {
                text: parent.text
                textFormat: Text.PlainText
                color: parent.tint
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        function tintOf(colorName, fallback) {
            var h = Colors.hex(colorName || "");
            return h !== "" ? h : fallback;
        }

        // the date: click to keep the words in the title instead
        PlasmaComponents3.ToolButton {
            readonly property var d: field.parsed ? field.parsed.date : null
            visible: !!d
            icon.name: "view-calendar-day"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            text: d && field.controller ? field.controller.dateText(d.key) + (d.minutes !== null ? " " + field.controller.timeText(d.minutes) : "") : ""
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.strikeout: field.keepDateText
            topPadding: 0
            bottomPadding: 0
            focusPolicy: Qt.NoFocus
            Accessible.description: tip.text
            onClicked: field.keepDateText = !field.keepDateText
            PlasmaComponents3.ToolTip {
                id: tip
                text: field.keepDateText ? Lang.i18n("Click to use this as the date") : Lang.i18n("Click to keep these words in the title instead")
                visible: parent.hovered
                delay: Kirigami.Units.toolTipDelay
            }
        }
        Tag {
            visible: !!field.parsed && field.parsed.recurring
            iconName: "view-refresh"
            text: Lang.i18n("Repeats (Todoist reads the schedule)")
            opacity: 0.8
        }
        Tag {
            readonly property var p: field.parsed ? field.parsed.project : null
            visible: !!p
            text: p ? (p.known ? "# " + p.name : Lang.i18n("#%1 isn't a project: it stays in the title", p.name)) : ""
            tint: p && p.known ? preview.tintOf(p.color, Kirigami.Theme.textColor) : Kirigami.Theme.neutralTextColor
        }
        Repeater {
            model: field.parsed ? field.parsed.labels : []
            delegate: Tag {
                required property var modelData
                text: modelData.known ? "@" + modelData.name : Lang.i18n("@%1 (new label)", modelData.name)
                tint: preview.tintOf(modelData.color, Kirigami.Theme.textColor)
            }
        }
        Tag {
            readonly property int p: field.parsed ? field.parsed.priority : 0
            visible: p > 0
            iconName: "flag"
            text: Lang.i18n("Priority %1", p)
            tint: p === 1 ? Kirigami.Theme.negativeTextColor : p === 2 ? Kirigami.Theme.neutralTextColor
                : p === 3 ? Kirigami.Theme.linkColor : Kirigami.Theme.textColor
        }
    }
}
