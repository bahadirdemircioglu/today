import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Settings → Appearance: language, colours, density and the desktop background.
KCM.SimpleKCM {
    id: page

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

    Kirigami.FormLayout {
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
    }
}
