import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "logic/TodoistClient.js" as TodoistClient

// Settings window page (QQC2, not PlasmaComponents). Writes only cfg_apiToken / cfg_accountName;
// after Apply the widget sees the token change and runs the same TOKEN_SET flow as SetupView.
KCM.SimpleKCM {
    id: page

    property string cfg_apiToken
    property string cfg_apiTokenDefault: ""
    property string cfg_accountName
    property string cfg_accountNameDefault: ""
    property string cfg_pinnedView
    property string cfg_pinnedViewDefault: ""
    property string cfg_badgeSource
    property string cfg_badgeSourceDefault: "today"
    property string cfg_language
    property string cfg_languageDefault: ""
    property string cfg_priorityColors
    property string cfg_priorityColorsDefault: "plasma"
    property bool cfg_projectStripe
    property bool cfg_projectStripeDefault: true
    property string cfg_desktopBackground
    property string cfg_desktopBackgroundDefault: "standard"
    property string cfg_density
    property string cfg_densityDefault: "comfortable"
    property bool cfg_showGoal
    property bool cfg_showGoalDefault: true
    property int cfg_notifyLeadMinutes
    property int cfg_notifyLeadMinutesDefault: 10
    property string cfg_customQuery
    property string cfg_customQueryDefault: ""
    property string cfg_customQueryName
    property string cfg_customQueryNameDefault: ""

    readonly property string tokenUrl: "https://app.todoist.com/app/settings/integrations/developer"

    property bool checking: false
    property string status: ""
    property bool statusIsError: false
    property int generation: 0

    function verify() {
        var t = tokenField.text.trim();
        debounce.stop();
        if (!t) {
            return;
        }
        var gen = ++generation;
        checking = true;
        status = "";
        TodoistClient.getUser(t, function (res) {
            if (gen !== page.generation) {
                return;
            }
            page.checking = false;
            if (res.kind === "ok" && res.json) {
                page.cfg_accountName = res.json.full_name || res.json.email || "";
                page.statusIsError = false;
                page.status = Lang.i18n("Token works.");
                return;
            }
            page.statusIsError = true;
            if (res.kind === "auth") {
                page.status = Lang.i18n("This token didn't work. Copy it again from Todoist settings.");
            } else if (res.kind === "network") {
                page.status = Lang.i18n("Can't reach Todoist. Check your connection.");
            } else {
                page.status = Lang.i18n("Something went wrong (HTTP %1).", res.status);
            }
        });
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: page.verify()
    }

    Component.onCompleted: tokenField.text = cfg_apiToken

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: Lang.i18n("Account:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: page.cfg_apiToken === "" ? Lang.i18n("Not connected")
                    : (page.cfg_accountName !== "" ? Lang.i18n("Connected as %1", page.cfg_accountName) : Lang.i18n("Connected"))
                textFormat: Text.PlainText
            }
            QQC2.Button {
                visible: page.cfg_apiToken !== ""
                text: Lang.i18n("Disconnect")
                icon.name: "network-disconnect"
                onClicked: {
                    tokenField.text = "";
                    page.cfg_apiToken = "";
                    page.cfg_accountName = "";
                    page.status = "";
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: Lang.i18n("API token:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: tokenField
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                placeholderText: Lang.i18n("Paste your API token")
                echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onTextEdited: {
                    page.cfg_apiToken = text.trim();
                    page.cfg_accountName = "";
                    page.status = "";
                    if (text.trim().length >= 32) {
                        debounce.restart();
                    }
                }
                onAccepted: page.verify()
            }
            QQC2.ToolButton {
                id: reveal
                checkable: true
                icon.name: checked ? "password-show-off" : "password-show-on"
                text: checked ? Lang.i18n("Hide token") : Lang.i18n("Show token")
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
            }
        }

        QQC2.Button {
            icon.name: "internet-services"
            text: Lang.i18n("Open Todoist settings")
            onClicked: Qt.openUrlExternally(page.tokenUrl)
        }

        RowLayout {
            visible: page.checking || page.status !== ""
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                visible: page.checking
                running: visible
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
            QQC2.Label {
                text: page.checking ? Lang.i18n("Checking…") : page.status
                textFormat: Text.PlainText
                color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: Lang.i18n("Your token is stored unencrypted in your Plasma config file. You can revoke it any time in Todoist's settings.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: Lang.i18n("Language:")
            textRole: "text"
            valueRole: "value"
            // every language with a catalog, by its own name, plus English (the source language)
            model: [{ value: "", text: Lang.i18n("System default") }].concat(
                ["en"].concat(Lang.available).map(function (code) {
                    var name = Qt.locale(code).nativeLanguageName || code;
                    return { value: code, text: name.charAt(0).toUpperCase() + name.slice(1) };
                }))
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_language))
            onActivated: page.cfg_language = currentValue
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: Lang.i18n("Applies to all Todoist for Plasma widgets.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: Lang.i18n("Appearance")
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: Lang.i18n("Priority colours:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "plasma", text: Lang.i18n("From the Plasma theme") },
                { value: "todoist", text: Lang.i18n("Todoist's red, orange and blue") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_priorityColors))
            onActivated: page.cfg_priorityColors = currentValue
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: Lang.i18n("Project colour:")
            text: Lang.i18n("Show a colour strip beside each task")
            checked: page.cfg_projectStripe
            onToggled: page.cfg_projectStripe = checked
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: Lang.i18n("Desktop background:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "standard", text: Lang.i18n("Standard") },
                { value: "translucent", text: Lang.i18n("Translucent") },
                { value: "none", text: Lang.i18n("None (text gets a soft shadow)") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_desktopBackground))
            onActivated: page.cfg_desktopBackground = currentValue
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: Lang.i18n("Density:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "comfortable", text: Lang.i18n("Comfortable") },
                { value: "compact", text: Lang.i18n("Compact: more tasks fit") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_density))
            onActivated: page.cfg_density = currentValue
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: badgeCombo
            Kirigami.FormData.label: Lang.i18n("Panel badge:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "today", text: Lang.i18n("Overdue and today's tasks") },
                { value: "view", text: Lang.i18n("Tasks in the current list") },
                { value: "none", text: Lang.i18n("No badge") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_badgeSource))
            onActivated: page.cfg_badgeSource = currentValue
        }

        QQC2.TextField {
            id: queryField
            Kirigami.FormData.label: Lang.i18n("Custom filter:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            placeholderText: Lang.i18n("e.g. today & #Work")
            Component.onCompleted: text = page.cfg_customQuery
            onTextEdited: page.cfg_customQuery = text
        }
        QQC2.TextField {
            Kirigami.FormData.label: Lang.i18n("Shown as:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            enabled: queryField.text.trim() !== ""
            placeholderText: Lang.i18n("Custom filter")
            Component.onCompleted: text = page.cfg_customQueryName
            onTextEdited: page.cfg_customQueryName = text
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: Lang.i18n("Any Todoist filter query, without saving it in Todoist. It appears in the list menu.")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: Lang.i18n("Daily goal:")
            text: Lang.i18n("Show progress towards my Todoist daily goal")
            checked: page.cfg_showGoal
            onToggled: page.cfg_showGoal = checked
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: Lang.i18n("Reminders:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: -1, text: Lang.i18n("Off") },
                { value: 0, text: Lang.i18n("At the task's time") },
                { value: 5, text: Lang.i18n("5 minutes before") },
                { value: 10, text: Lang.i18n("10 minutes before") },
                { value: 15, text: Lang.i18n("15 minutes before") },
                { value: 30, text: Lang.i18n("30 minutes before") },
                { value: 60, text: Lang.i18n("1 hour before") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_notifyLeadMinutes))
            onActivated: page.cfg_notifyLeadMinutes = currentValue
        }

        RowLayout {
            Kirigami.FormData.label: Lang.i18n("Start with:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: page.cfg_pinnedView === "" ? Lang.i18n("The list you used last")
                                                 : Lang.i18n("A pinned list (set from the list title menu)")
            }
            QQC2.Button {
                visible: page.cfg_pinnedView !== ""
                text: Lang.i18n("Unpin")
                icon.name: "window-unpin"
                onClicked: page.cfg_pinnedView = ""
            }
        }
    }
}
