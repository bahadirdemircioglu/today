import QtQuick

import org.kde.notification

// Plasma notifications for timed tasks. Loaded through a Loader in main.qml: if the
// org.kde.notification module is missing, only reminders are lost, never the widget.
Item {
    id: notifier

    property var controller

    function show(itemId, title, body, baseKey) {
        var n = notificationComponent.createObject(notifier, {
            title: title,
            text: body,
            itemId: itemId,
            baseKey: baseKey
        });
        if (n) {
            n.sendEvent();
        }
    }

    Component {
        id: notificationComponent

        Notification {
            id: notification

            property string itemId
            property string baseKey

            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "view-calendar-tasks"
            autoDelete: true
            actions: [
                NotificationAction {
                    label: i18n("Complete")
                    onActivated: notifier.controller.complete(notification.itemId, notification.title)
                },
                NotificationAction {
                    label: i18n("Remind me in 10 minutes")
                    onActivated: notifier.controller.snooze(notification.baseKey)
                }
            ]
        }
    }
}
