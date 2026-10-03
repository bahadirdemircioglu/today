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
                page.status = i18n("Token works.");
                return;
            }
            page.statusIsError = true;
            if (res.kind === "auth") {
                page.status = i18n("This token didn't work. Copy it again from Todoist settings.");
            } else if (res.kind === "network") {
                page.status = i18n("Can't reach Todoist. Check your connection.");
            } else {
                page.status = i18n("Something went wrong (HTTP %1).", res.status);
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
            Kirigami.FormData.label: i18n("Account:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: page.cfg_apiToken === "" ? i18n("Not connected")
                    : (page.cfg_accountName !== "" ? i18n("Connected as %1", page.cfg_accountName) : i18n("Connected"))
                textFormat: Text.PlainText
            }
            QQC2.Button {
                visible: page.cfg_apiToken !== ""
                text: i18n("Disconnect")
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
            Kirigami.FormData.label: i18n("API token:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: tokenField
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                placeholderText: i18n("Paste your API token")
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
                text: checked ? i18n("Hide token") : i18n("Show token")
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
            }
        }

        QQC2.Button {
            icon.name: "internet-services"
            text: i18n("Open Todoist settings")
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
                text: page.checking ? i18n("Checking…") : page.status
                textFormat: Text.PlainText
                color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: i18n("Your token is stored unencrypted in your Plasma config file. You can revoke it any time in Todoist's settings.")
        }
    }
}
