import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                    || Plasmoid.formFactor === PlasmaCore.Types.Vertical

    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    // Settings → Appearance → Desktop background; "standard" can still be switched off in edit mode
    readonly property string desktopBackground: Plasmoid.configuration.desktopBackground
    Plasmoid.backgroundHints: desktopBackground === "translucent" ? PlasmaCore.Types.TranslucentBackground
        : desktopBackground === "none" ? PlasmaCore.Types.NoBackground
        : PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    // below this size on the desktop Plasma falls back to the compact (icon) form
    switchWidth: Kirigami.Units.gridUnit * 8
    switchHeight: Kirigami.Units.gridUnit * 6

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
        controller: sync
    }
    fullRepresentation: FullRepresentation {
        plasmoidItem: root
        controller: sync
    }

    toolTipMainText: Lang.i18n("Todoist for Plasma")
    toolTipSubText: {
        switch (sync.phase) {
        case "SETUP":
            return Lang.i18n("Not connected to Todoist");
        case "AUTH_INVALID":
            return Lang.i18n("Todoist didn't accept your token");
        case "LOADING":
            if (!sync.hasCache) {
                return Lang.i18n("Loading your tasks…");
            }
            break;
        }
        if (sync.todayCount === 0) {
            return Lang.i18n("All done for today");
        }
        var text = Lang.i18np("%1 task today", "%1 tasks today", sync.todayCount);
        var next = sync.todayView.next;
        if (next) {
            var when = sync.timeText(next.minutes);
            text += " · " + (when ? Lang.i18nc("next task: title time", "Next: %1 %2", next.title, when)
                                  : Lang.i18nc("next task: title", "Next: %1", next.title));
        }
        return text;
    }

    // Language: one Lang object serves every widget in this Plasma session, so the widgets
    // share the setting. A widget that loads later adopts a language another one already set.
    function applyLanguage() {
        var mine = Plasmoid.configuration.language;
        if (!Lang.configured) {
            Lang.configured = true;
            Lang.code = mine;
        } else if (mine !== "" && Lang.code === "") {
            Lang.code = mine;
        } else if (mine !== Lang.code) {
            Plasmoid.configuration.language = Lang.code;
        }
    }
    readonly property string configuredLanguage: Plasmoid.configuration.language
    onConfiguredLanguageChanged: Lang.code = configuredLanguage
    Component.onCompleted: applyLanguage()
    Connections {
        target: Lang
        function onCodeChanged() {
            if (Plasmoid.configuration.language !== Lang.code) {
                Plasmoid.configuration.language = Lang.code;
            }
        }
    }

    // Global shortcut (Configure… → Keyboard Shortcuts): Plasma opens the popup in a panel;
    // either way the "New task" field takes the focus, like Todoist's global Quick Add.
    Connections {
        target: Plasmoid
        function onActivated() {
            sync.requestNewTaskFocus();
        }
    }

    onExpandedChanged: {
        if (expanded) {
            sync.requestSync("expanded");
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: Lang.i18n("Refresh now")
            icon.name: "view-refresh"
            enabled: sync.phase !== "SETUP"
            onTriggered: sync.requestSync("manual")
        },
        PlasmaCore.Action {
            text: Lang.i18n("Open Todoist")
            icon.name: "internet-services"
            onTriggered: Qt.openUrlExternally("https://app.todoist.com/app/today")
        }
    ]

    Loader {
        id: notifierLoader
        source: "Notifier.qml"
        onLoaded: item.controller = sync
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[todoist-plasma] notifications unavailable (org.kde.notification missing)");
            }
        }
    }

    SyncController {
        id: sync
        token: Plasmoid.configuration.apiToken
        appletId: String(Plasmoid.id)
        pinnedView: Plasmoid.configuration.pinnedView
        badgeSource: Plasmoid.configuration.badgeSource
        customQuery: Plasmoid.configuration.customQuery
        customQueryName: Plasmoid.configuration.customQueryName
        notifyLeadMinutes: Plasmoid.configuration.notifyLeadMinutes
        showGoal: Plasmoid.configuration.showGoal
        priorityColors: Plasmoid.configuration.priorityColors
        projectStripe: Plasmoid.configuration.projectStripe
        density: Plasmoid.configuration.density
        onPinnedViewRemapped: key => {
            Plasmoid.configuration.pinnedView = key;
        }
        onReminderDue: (itemId, title, body, baseKey) => {
            if (notifierLoader.item) {
                notifierLoader.item.show(itemId, title, body, baseKey);
            }
        }
        onAccountVerified: name => {
            if (name && Plasmoid.configuration.accountName !== name) {
                Plasmoid.configuration.accountName = name;
            }
        }
    }
}
