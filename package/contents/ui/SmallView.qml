import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Small desktop size: big count + the next task.
ColumnLayout {
    id: small

    property var controller

    readonly property var next: controller ? controller.nextTask : null
    readonly property int count: controller ? controller.count : 0
    readonly property int overdue: controller ? controller.overdueCount : 0

    spacing: Kirigami.Units.smallSpacing

    Item { Layout.fillHeight: true }

    PlasmaComponents3.Label {
        Layout.alignment: Qt.AlignHCenter
        text: small.count
        textFormat: Text.PlainText
        font.pixelSize: Kirigami.Units.gridUnit * 2.5
        font.weight: Font.Light
        color: small.overdue > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    }

    PlasmaComponents3.Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: small.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        opacity: 0.7
        text: {
            var title = small.controller ? small.controller.viewTitle : "";
            if (small.count === 0) {
                return small.controller && small.controller.viewSpec.kind === "today" ? i18n("All done for today") : title;
            }
            if (small.overdue > 0) {
                return i18np("%2 · %1 overdue", "%2 · %1 overdue", small.overdue, title);
            }
            return title;
        }
    }

    PlasmaComponents3.Label {
        visible: small.next !== null
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: {
            if (!small.next) {
                return "";
            }
            var when = small.controller.timeText(small.next.minutes);
            return when ? when + "  " + small.next.title : small.next.title;
        }
    }

    Item { Layout.fillHeight: true }

    TapHandler {
        onTapped: Qt.openUrlExternally("https://app.todoist.com/app/today")
    }
}
