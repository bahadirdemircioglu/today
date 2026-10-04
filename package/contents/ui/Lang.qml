pragma Singleton

import QtQuick

import "logic/I18n.js" as I18n
import "logic/Catalogs.js" as Catalogs

// The widget's language. KDE's i18n() always follows the system language, so the widget
// translates through this object instead: Lang.i18n("…"), Lang.i18nc(…), Lang.i18np(…).
// Bindings that use it re-evaluate when the language changes.
QtObject {
    // "" = follow the system; otherwise a language code ("en", "tr", …). Set by main.qml.
    property string code: ""
    // set once the first widget has applied its configuration
    property bool configured: false

    readonly property var available: Object.keys(Catalogs.CATALOGS)
    readonly property string effective: I18n.pickLanguage(code, Qt.locale().uiLanguages, available)
    // month and day names in the chosen language; the system locale when it already matches
    readonly property var locale: {
        var sys = Qt.locale();
        if (code === "" || I18n.pickLanguage("", [sys.name], available.concat(["en"])) === effective) {
            return sys;
        }
        return Qt.locale(effective);
    }

    function i18n(text, ...args) {
        return I18n.translate(Catalogs.CATALOGS, effective, "", text, args);
    }
    function i18nc(context, text, ...args) {
        return I18n.translate(Catalogs.CATALOGS, effective, context, text, args);
    }
    function i18np(singular, plural, n, ...args) {
        return I18n.translatePlural(Catalogs.CATALOGS, effective, "", singular, plural, n, args);
    }
    function formatDate(date, format) {
        return date.toLocaleDateString(locale, format);
    }
    // the time in the system's format (12/24 h), with names from the chosen language
    function formatTime(date) {
        return date.toLocaleTimeString(locale, Qt.locale().timeFormat(Locale.ShortFormat));
    }
}
