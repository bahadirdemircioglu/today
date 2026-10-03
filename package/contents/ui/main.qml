import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                    || Plasmoid.formFactor === PlasmaCore.Types.Vertical

    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
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

    toolTipMainText: i18n("Todoist for Plasma")
    toolTipSubText: {
        switch (sync.phase) {
        case "SETUP":
            return i18n("Not connected to Todoist");
        case "AUTH_INVALID":
            return i18n("Todoist didn't accept your token");
        case "LOADING":
            if (!sync.hasCache) {
                return i18n("Loading your tasks…");
            }
            break;
        }
        if (sync.count === 0) {
            return i18n("All done for today");
        }
        var text = i18np("%1 task today", "%1 tasks today", sync.count);
        var next = sync.view.next;
        if (next) {
            var when = sync.timeText(next.minutes);
            text += " · " + (when ? i18nc("next task: title time", "Next: %1 %2", next.title, when)
                                  : i18nc("next task: title", "Next: %1", next.title));
        }
        return text;
    }

    onExpandedChanged: {
        if (expanded) {
            sync.requestSync("expanded");
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            enabled: sync.phase !== "SETUP"
            onTriggered: sync.requestSync("manual")
        },
        PlasmaCore.Action {
            text: i18n("Open Todoist")
            icon.name: "internet-services"
            onTriggered: Qt.openUrlExternally("https://app.todoist.com/app/today")
        }
    ]

    SyncController {
        id: sync
        token: Plasmoid.configuration.apiToken
        appletId: String(Plasmoid.id)
        onAccountVerified: name => {
            if (name && Plasmoid.configuration.accountName !== name) {
                Plasmoid.configuration.accountName = name;
            }
        }
    }
}
