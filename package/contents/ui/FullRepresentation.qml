import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Picks the view for the current state and size (popup or desktop).
Item {
    id: full

    property PlasmoidItem plasmoidItem
    property var controller

    readonly property bool inPopup: plasmoidItem ? plasmoidItem.inPanel : false
    readonly property string phase: controller ? controller.phase : "SETUP"
    readonly property bool small: !inPopup
        && (width < Kirigami.Units.gridUnit * 14 || height < Kirigami.Units.gridUnit * 12)

    // On the desktop without a background, a soft shadow (or glow, for dark text) keeps the
    // text readable over any wallpaper.
    // (shader effects need a GPU renderer: with Qt's software renderer the item would vanish)
    readonly property bool bare: !inPopup && Plasmoid.effectiveBackgroundHints === PlasmaCore.Types.NoBackground
    readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    layer.enabled: bare && gpu
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.35
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 1
        shadowColor: Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(0, 0, 0, 0.9) : Qt.rgba(1, 1, 1, 0.9)
    }

    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 26
    Layout.minimumWidth: Kirigami.Units.gridUnit * (inPopup ? 16 : 8)
    Layout.minimumHeight: Kirigami.Units.gridUnit * (inPopup ? 12 : 6)

    // No reliable "became visible" signal on the desktop: hovering is the cheapest native
    // sign of interest, so stale data (> 30 s, decided by SyncMachine) is refreshed then.
    HoverHandler {
        onHoveredChanged: {
            if (hovered && !full.inPopup && full.controller) {
                full.controller.requestSync("hover");
            }
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            if (!full.controller || full.phase === "SETUP") {
                return setupComponent;
            }
            if (!full.controller.hasCache) {
                switch (full.phase) {
                case "LOADING":
                    return loadingComponent;
                case "OFFLINE":
                case "ERROR":
                    return unreachableComponent;
                case "AUTH_INVALID":
                    return setupComponent;
                }
            }
            return full.small ? smallComponent : listComponent;
        }
    }

    Component {
        id: setupComponent
        SetupView {
            compact: full.small
            authFailed: full.phase === "AUTH_INVALID"
        }
    }

    Component {
        id: loadingComponent
        ColumnLayout {
            Item { Layout.fillHeight: true }
            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: true
            }
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: Lang.i18n("Loading your tasks…")
                opacity: 0.7
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: unreachableComponent
        Item {
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                icon.name: full.phase === "OFFLINE" ? "network-disconnect" : "data-warning"
                text: full.phase === "OFFLINE" ? Lang.i18n("Can't reach Todoist") : Lang.i18n("Todoist is having trouble")
                helpfulAction: Kirigami.Action {
                    text: Lang.i18n("Try again")
                    icon.name: "view-refresh"
                    onTriggered: full.controller.requestSync("manual")
                }
            }
        }
    }

    Component {
        id: smallComponent
        SmallView {
            controller: full.controller
        }
    }

    Component {
        id: listComponent
        TaskListView {
            controller: full.controller
        }
    }
}
