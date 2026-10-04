.pragma library

// Runtime translation for a per-widget language choice. Same semantics as KDE's i18n():
// %1..%9 placeholders; for plurals %1 is the count and later arguments are %2, %3, …
// Catalogs come from Catalogs.js (generated from translations/*.po).

var SOURCE_LANGUAGE = "en";

// code: the configured language ("" = follow the system). uiLanguages: e.g. ["tr-TR", "en-US"].
// available: language codes that have a catalog. -> the language to show
function pickLanguage(code, uiLanguages, available) {
    function base(l) {
        return String(l || "").split(/[-_.@]/)[0].toLowerCase();
    }
    if (code) {
        var c = base(code);
        return available.indexOf(c) !== -1 ? c : SOURCE_LANGUAGE;
    }
    var list = uiLanguages || [];
    for (var i = 0; i < list.length; i++) {
        var b = base(list[i]);
        if (b === SOURCE_LANGUAGE || available.indexOf(b) !== -1) {
            return b;
        }
    }
    return SOURCE_LANGUAGE;
}

function substitute(text, args) {
    return String(text).replace(/%(\d)/g, function (m, d) {
        var i = Number(d) - 1;
        return i >= 0 && i < args.length && args[i] !== undefined && args[i] !== null ? String(args[i]) : m;
    });
}

function lookup(catalogs, lang, ctx, msgid) {
    var cat = catalogs[lang];
    if (!cat) {
        return undefined;
    }
    return cat.messages[ctx ? ctx + "\u0004" + msgid : msgid];
}

function translate(catalogs, lang, ctx, msgid, args) {
    var t = lookup(catalogs, lang, ctx, msgid);
    return substitute(typeof t === "string" ? t : msgid, args || []);
}

// args: the arguments after the count (they become %2, %3, …)
function translatePlural(catalogs, lang, ctx, singular, plural, n, args) {
    var t = lookup(catalogs, lang, ctx, singular);
    var text;
    if (Array.isArray(t)) {
        var form = catalogs[lang].plural(n);
        text = t[Math.min(Math.max(form, 0), t.length - 1)];
    } else {
        text = n === 1 ? singular : plural;
    }
    return substitute(text, [n].concat(args || []));
}
