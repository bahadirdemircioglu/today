import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic/TodoistClient.js" as TodoistClient
import "logic/Storage.js" as Storage

// In-widget, one-screen setup: open Todoist settings, paste the token, done.
// It only writes Plasmoid.configuration (the single source of truth); main.qml's
// SyncController reacts to the token change.
Item {
    id: setup

    property bool compact: false
    property bool authFailed: false

    readonly property string tokenUrl: "https://app.todoist.com/app/settings/integrations/developer"

    property bool checking: false
    property string status: ""
    property bool statusIsError: false
    property bool connected: false
    property int generation: 0
    property var xhr: null
    // an account another widget instance is already connected to
    property var sharedAccount: null

    Component.onCompleted: {
        var shared = Storage.loadShared("account");
        sharedAccount = shared && shared.token && !authFailed ? shared : null;
    }

    function useSharedAccount() {
        Plasmoid.configuration.accountName = sharedAccount.name || "";
        Plasmoid.configuration.apiToken = sharedAccount.token;
    }

    function tokenEdited() {
        status = "";
        connected = false;
        if (tokenField.text.trim().length >= 32) {
            debounce.restart();
        } else {
            debounce.stop();
        }
    }

    function verify() {
        var t = tokenField.text.trim();
        debounce.stop();
        if (!t) {
            return;
        }
        var gen = ++generation;
        if (xhr) {
            try {
                xhr.abort();
            } catch (e) {
                // ignore
            }
        }
        checking = true;
        status = "";
        xhr = TodoistClient.getUser(t, function (res) {
            if (gen !== setup.generation) {
                return;
            }
            setup.checking = false;
            setup.xhr = null;
            if (res.kind === "ok" && res.json) {
                var name = res.json.full_name || res.json.email || "";
                setup.connected = true;
                setup.statusIsError = false;
                setup.status = res.json.full_name && res.json.email
                    ? Lang.i18n("Connected as %1 (%2)", res.json.full_name, res.json.email)
                    : Lang.i18n("Connected as %1", name);
                Plasmoid.configuration.accountName = name;
                Plasmoid.configuration.apiToken = t;
                return;
            }
            setup.statusIsError = true;
            if (res.kind === "auth") {
                setup.status = Lang.i18n("This token didn't work. Copy it again from Todoist settings.");
            } else if (res.kind === "network") {
                setup.status = Lang.i18n("Can't reach Todoist. Check your connection.");
            } else {
                setup.status = Lang.i18n("Something went wrong (HTTP %1).", res.status);
            }
        });
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: setup.verify()
    }

    PlasmaComponents3.Button {
        visible: setup.compact
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width)
        icon.name: "view-calendar-tasks"
        text: Lang.i18n("Connect to Todoist…")
        onClicked: Plasmoid.internalAction("configure").trigger()
    }

    ColumnLayout {
        visible: !setup.compact
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Kirigami.Units.iconSizes.huge
            implicitHeight: Kirigami.Units.iconSizes.huge
            source: "view-calendar-tasks"
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Lang.i18n("Connect to Todoist")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: 0.8
            text: setup.authFailed
                ? Lang.i18n("Todoist didn't accept your token. Paste a new one to reconnect.")
                : Lang.i18n("Paste your personal API token from Todoist's settings to see today's tasks here.")
        }

        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignHCenter
            visible: setup.sharedAccount !== null
            icon.name: "user-identity"
            text: setup.sharedAccount ? (setup.sharedAccount.name ? Lang.i18n("Use the connected account (%1)", setup.sharedAccount.name)
                                                                   : Lang.i18n("Use the connected account"))
                                      : ""
            onClicked: setup.useSharedAccount()
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: setup.sharedAccount !== null
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: Lang.i18n("or connect a different account:")
        }

        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignHCenter
            icon.name: "internet-services"
            text: Lang.i18n("Open Todoist settings")
            onClicked: Qt.openUrlExternally(setup.tokenUrl)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.TextField {
                id: tokenField
                Layout.fillWidth: true
                placeholderText: Lang.i18n("Paste your API token")
                echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onTextChanged: setup.tokenEdited()
                onAccepted: setup.verify()
            }
            PlasmaComponents3.ToolButton {
                id: reveal
                checkable: true
                icon.name: checked ? "password-show-off" : "password-show-on"
                text: checked ? Lang.i18n("Hide token") : Lang.i18n("Show token")
                display: PlasmaComponents3.AbstractButton.IconOnly
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: setup.checking || setup.status !== ""
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.BusyIndicator {
                visible: setup.checking
                running: visible
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
            Kirigami.Icon {
                visible: setup.connected
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                source: "checkmark"
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: setup.checking ? Lang.i18n("Checking…") : setup.status
                color: setup.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            text: Lang.i18n("Your token is stored unencrypted in your Plasma config file.")
        }
    }
}
