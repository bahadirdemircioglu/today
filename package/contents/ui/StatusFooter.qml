import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// One quiet line: short info/errors, offline/error state, or "Updated N minutes ago" (only when > 10 min).
RowLayout {
    id: footer

    property var controller

    readonly property bool isError: !!controller && (controller.infoText !== "" ? controller.infoIsError
                                                                               : controller.phase === "ERROR")
    readonly property string message: {
        var c = controller;
        if (!c) {
            return "";
        }
        if (c.infoText !== "") {
            return c.infoText;
        }
        var waiting = c.queuedCount > 0
            ? " · " + i18np("%1 change waiting", "%1 changes waiting", c.queuedCount) : "";
        if (c.phase === "OFFLINE") {
            return i18n("Offline. Showing saved tasks.") + waiting;
        }
        if (c.phase === "ERROR") {
            return i18n("Todoist is having trouble. Retrying…") + waiting;
        }
        if (c.rateLimited) {
            return i18n("Todoist asked to slow down. Retrying soon…") + waiting;
        }
        if (c.phase === "READY" && c.lastSyncAt > 0) {
            var mins = Math.floor((c.nowMs - c.lastSyncAt) / 60000);
            if (mins > 10) {
                return i18np("Updated %1 minute ago", "Updated %1 minutes ago", mins) + waiting;
            }
        }
        return "";
    }

    visible: message !== ""
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small
        visible: footer.controller && (footer.isError || footer.controller.phase === "OFFLINE")
        source: footer.controller && footer.controller.phase === "OFFLINE" && !footer.isError
                ? "network-disconnect" : "data-warning"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: footer.message
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: footer.isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        opacity: footer.isError ? 1 : 0.7
    }
}
