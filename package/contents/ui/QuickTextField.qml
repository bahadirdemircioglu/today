import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/QuickParse.js" as QuickParse
import "logic/Colors.js" as Colors

// A text field that reads Todoist Quick Add syntax as you type (see QuickParse.js): #project and
// @label suggestions, and a preview of the date, project, labels and priority it will apply.
// Used for new tasks (NewTaskField) and for editing a task (TaskRow), where the task's current
// date and project are shown too and can be removed.
ColumnLayout {
    id: field

    property var controller
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias inputObjectName: input.objectName
    readonly property alias inputActiveFocus: input.activeFocus

    // a trailing button beside the field ("" = none)
    property string buttonText: ""
    property string buttonIcon: "list-add"

    // editing: the task's current date and project ("" = none), and whether the user removed them
    property string currentDate: ""
    property string currentProject: ""
    property string currentProjectColor: ""
    property bool clearDate: false
    property bool clearProject: false

    signal submitted()
    signal cancelled()
    signal upFromEmpty()
    signal focusLost()

    spacing: Kirigami.Units.smallSpacing / 2

    function forceInputFocus() {
        input.forceActiveFocus();
    }
    function selectAll() {
        input.selectAll();
    }
    function reset() {
        input.text = "";
        keepDateText = false;
        clearDate = false;
        clearProject = false;
    }

    // live reading of the text (see QuickParse.js)
    readonly property var parsed: controller && input.text.trim() !== "" ? controller.parseQuickAdd(input.text) : null
    // the user clicked the date chip: keep the words as typed
    property bool keepDateText: false
    readonly property var typedDate: parsed && parsed.date && !keepDateText
                                     && QuickParse.stripSpans(input.text, parsed.date.spans) !== "" ? parsed.date : null
    readonly property var typedProject: parsed && parsed.project && parsed.project.known ? parsed.project : null

    // #project / @label suggestions for the word at the cursor (Esc hides them until the text changes)
    property bool completionDismissed: false
    readonly property var completion: controller && input.activeFocus && !completionDismissed
                                      ? controller.completeQuickAdd(input.text, input.cursorPosition) : null
    property int completionIndex: 0
    onCompletionChanged: completionIndex = 0

    function acceptCompletion(item) {
        var r = QuickParse.applyCompletion(input.text, completion, item);
        input.text = r.text;
        input.cursorPosition = r.cursor;
        input.forceActiveFocus();
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.TextField {
            id: input
            Layout.fillWidth: true
            onAccepted: field.submitted()
            onActiveFocusChanged: {
                if (!activeFocus) {
                    field.focusLost();
                }
            }
            Keys.onEscapePressed: {
                if (field.completion) {
                    field.completionDismissed = true;
                    return;
                }
                field.cancelled();
            }
            onTextChanged: {
                field.completionDismissed = false;
                if (text === "") {
                    field.keepDateText = false;
                }
            }
            // with suggestions open: ↑/↓ choose, Tab or Enter completes, Esc closes them
            Keys.onTabPressed: event => {
                event.accepted = !!field.completion;
                if (event.accepted) {
                    field.acceptCompletion(field.completion.items[field.completionIndex]);
                }
            }
            Keys.onReturnPressed: event => {
                event.accepted = !!field.completion;
                if (event.accepted) {
                    field.acceptCompletion(field.completion.items[field.completionIndex]);
                }
            }
            Keys.onEnterPressed: event => {
                event.accepted = !!field.completion;
                if (event.accepted) {
                    field.acceptCompletion(field.completion.items[field.completionIndex]);
                }
            }
            Keys.onDownPressed: event => {
                event.accepted = !!field.completion;
                if (event.accepted) {
                    field.completionIndex = (field.completionIndex + 1) % field.completion.items.length;
                }
            }
            Keys.onUpPressed: event => {
                if (field.completion) {
                    var n = field.completion.items.length;
                    field.completionIndex = (field.completionIndex + n - 1) % n;
                    event.accepted = true;
                    return;
                }
                event.accepted = text === "";
                if (event.accepted) {
                    field.upFromEmpty();
                }
            }
        }

        PlasmaComponents3.ToolButton {
            visible: field.buttonText !== ""
            icon.name: field.buttonIcon
            text: field.buttonText
            display: PlasmaComponents3.AbstractButton.IconOnly
            enabled: input.text.trim() !== ""
            onClicked: field.submitted()
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    // #project / @label suggestions
    ColumnLayout {
        Layout.fillWidth: true
        visible: !!field.completion
        spacing: 0

        Repeater {
            model: field.completion ? field.completion.items : []
            delegate: PlasmaComponents3.ItemDelegate {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                highlighted: index === field.completionIndex
                focusPolicy: Qt.NoFocus
                topPadding: Kirigami.Units.smallSpacing / 2
                bottomPadding: Kirigami.Units.smallSpacing / 2
                onClicked: field.acceptCompletion(modelData)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: field.completion && field.completion.kind === "project" ? "#" : "@"
                        color: Colors.hex(modelData.color) || Kirigami.Theme.disabledTextColor
                        font.weight: Font.DemiBold
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                }
            }
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: Lang.i18n("Tab or Enter to complete, ↑↓ to choose")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
        }
    }

    // Live preview: date, project, labels and priority as Todoist will read them
    Flow {
        id: preview
        Layout.fillWidth: true
        visible: (!!field.parsed && (!!field.parsed.date || field.parsed.recurring || !!field.parsed.project
                                     || field.parsed.labels.length > 0 || field.parsed.priority > 0))
                 || currentDateChip.visible || currentProjectChip.visible
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

        // editing: the task's current date / project; click to remove it (click again to keep it)
        PlasmaComponents3.ToolButton {
            id: currentDateChip
            visible: field.currentDate !== "" && !field.typedDate
            icon.name: field.clearDate ? "edit-undo" : "edit-clear"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            text: field.currentDate
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.strikeout: field.clearDate
            topPadding: 0
            bottomPadding: 0
            focusPolicy: Qt.NoFocus
            onClicked: field.clearDate = !field.clearDate
            PlasmaComponents3.ToolTip.text: field.clearDate ? Lang.i18n("Keep the date") : Lang.i18n("Remove the date")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        PlasmaComponents3.ToolButton {
            id: currentProjectChip
            visible: field.currentProject !== "" && !field.typedProject
            icon.name: field.clearProject ? "edit-undo" : "edit-clear"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            text: "# " + field.currentProject
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.strikeout: field.clearProject
            palette.buttonText: preview.tintOf(field.currentProjectColor, Kirigami.Theme.textColor)
            topPadding: 0
            bottomPadding: 0
            focusPolicy: Qt.NoFocus
            onClicked: field.clearProject = !field.clearProject
            PlasmaComponents3.ToolTip.text: field.clearProject ? Lang.i18n("Keep it in this project") : Lang.i18n("Move it to the Inbox")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
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
            // while its name is still being typed, the suggestions above show the choices
            visible: !!p && !(field.completion && field.completion.kind === "project")
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
            // p1 … p4 as typed = API priority 4 … 1
            readonly property bool todoist: !!field.controller && field.controller.priorityColors === "todoist"
            tint: todoist && Colors.priorityHex(5 - p) !== "" ? Colors.priorityHex(5 - p)
                : p === 1 ? Kirigami.Theme.negativeTextColor : p === 2 ? Kirigami.Theme.neutralTextColor
                : p === 3 ? Kirigami.Theme.linkColor : Kirigami.Theme.textColor
        }
    }
}
