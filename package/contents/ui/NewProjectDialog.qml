import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/Colors.js" as Colors

// "New project…": name, a Todoist colour and an optional parent project.
QQC2.Popup {
    id: dialog

    property var controller
    property string color: "charcoal"
    property string error: ""

    readonly property var colorNames: Object.keys(Colors.TODOIST)
    // parents: every real project except the Inbox
    readonly property var parents: controller ? controller.projects.filter(function (p) { return !p.isInbox; }) : []

    function openDialog() {
        nameField.text = "";
        color = "charcoal";
        parentBox.currentIndex = 0;
        error = "";
        open();
        nameField.forceActiveFocus();
    }

    function create() {
        var parentId = parentBox.currentIndex > 0 ? parents[parentBox.currentIndex - 1].id : "";
        var err = controller.createProject(nameField.text, color, parentId);
        if (err === "empty") {
            error = Lang.i18n("Give the project a name.");
            return;
        }
        if (err === "too_long") {
            error = Lang.i18n("That name is too long.");
            return;
        }
        close();
    }

    modal: true
    focus: true
    anchors.centerIn: QQC2.Overlay.overlay
    width: Math.min(Kirigami.Units.gridUnit * 19, parent ? parent.width - Kirigami.Units.gridUnit : Kirigami.Units.gridUnit * 19)
    padding: Kirigami.Units.largeSpacing

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 4
            text: Lang.i18n("New project")
        }

        PlasmaComponents3.TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Lang.i18n("Project name")
            onAccepted: dialog.create()
            onTextEdited: dialog.error = ""
        }

        PlasmaComponents3.Label {
            text: Lang.i18n("Colour")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: dialog.colorNames
                delegate: QQC2.AbstractButton {
                    required property string modelData
                    readonly property bool chosen: dialog.color === modelData
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium + 4
                    implicitHeight: implicitWidth
                    hoverEnabled: true
                    focusPolicy: Qt.TabFocus
                    Accessible.name: modelData.replace(/_/g, " ")
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: chosen
                    onClicked: dialog.color = modelData

                    background: Rectangle {
                        radius: width / 2
                        color: "transparent"
                        border.width: parent.chosen || parent.visualFocus ? 2 : 0
                        border.color: Kirigami.Theme.highlightColor
                    }
                    contentItem: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.small
                            height: width
                            radius: width / 2
                            color: Colors.hex(modelData)
                        }
                    }
                    PlasmaComponents3.ToolTip.text: Accessible.name
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: dialog.parents.length > 0
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: Lang.i18n("Inside:")
            }
            PlasmaComponents3.ComboBox {
                id: parentBox
                Layout.fillWidth: true
                model: [Lang.i18n("No parent project")].concat(dialog.parents.map(function (p) { return p.name; }))
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: dialog.error !== ""
            text: dialog.error
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Button {
                text: Lang.i18n("Cancel")
                onClicked: dialog.close()
            }
            PlasmaComponents3.Button {
                text: Lang.i18n("Create")
                icon.name: "list-add"
                onClicked: dialog.create()
            }
        }
    }
}
