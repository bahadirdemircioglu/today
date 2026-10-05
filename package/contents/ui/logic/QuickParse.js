.pragma library

.import "DateUtil.js" as DateUtil

// Reads what a Quick Add text will do, for the live preview under "New task", and recognises
// common English and Turkish dates so they work whatever language the Todoist account uses
// (Todoist's own parser only knows some languages).
//
// parse(text, opts) opts: { todayKey, nowMinutes, projects: [{ id, name, color }], labels: [{ name, color }] }
// -> { date: { key, minutes, spans: [[start, end]] } | null,
//      recurring: bool (a repeating schedule: left to Todoist),
//      project: { name, id, color, known } | null,
//      labels: [{ name, color, known }],
//      priority: 1..4 as typed (p1 = 1), 0 = none }

var END = "(?=$|[\\s,.;:!?])";

// 0 = Sunday, like DateUtil.weekdayOfKey
var WEEKDAYS_EN = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
var WEEKDAYS_TR = ["pazar", "pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi"];

var MONTHS = [
    ["january", "jan", "ocak"],
    ["february", "feb", "şubat", "subat"],
    ["march", "mar", "mart"],
    ["april", "apr", "nisan"],
    ["may", "mayıs", "mayis"],
    ["june", "jun", "haziran"],
    ["july", "jul", "temmuz"],
    ["august", "aug", "ağustos", "agustos"],
    ["september", "sept", "sep", "eylül", "eylul"],
    ["october", "oct", "ekim"],
    ["november", "nov", "kasım", "kasim"],
    ["december", "dec", "aralık", "aralik"]
];

function monthIndex(word) {
    var w = lower(word);
    for (var i = 0; i < MONTHS.length; i++) {
        if (MONTHS[i].indexOf(w) !== -1) {
            return i;
        }
    }
    return -1;
}

var MONTH_RE = MONTHS.map(function (m) { return m.join("|"); }).join("|");

// Turkish-aware enough for the words above (İ -> i, I -> ı would break English, so only İ)
function lower(s) {
    return String(s).replace(/İ/g, "i").toLowerCase();
}

function count(word) {
    var w = lower(word);
    if (w === "a" || w === "an" || w === "one" || w === "bir") {
        return 1;
    }
    var n = parseInt(w, 10);
    return isNaN(n) ? null : n;
}

function weekdayIndex(word) {
    var w = lower(word);
    var i = WEEKDAYS_EN.indexOf(w);
    return i !== -1 ? i : WEEKDAYS_TR.indexOf(w);
}

// next day with weekday wd: today counts unless strictlyAfter
function nextWeekday(todayKey, wd, strictlyAfter) {
    var diff = (wd - DateUtil.weekdayOfKey(todayKey) + 7) % 7;
    if (diff === 0 && strictlyAfter) {
        diff = 7;
    }
    return DateUtil.addDaysKey(todayKey, diff);
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

function explicitDate(todayKey, day, month, yearText) {
    var t = DateUtil.splitDateKey(todayKey);
    var y = yearText ? parseInt(yearText, 10) : t.y;
    var d = parseInt(day, 10);
    var probe = new Date(Date.UTC(y, month, d));
    if (d < 1 || probe.getUTCMonth() !== month) {
        return null;
    }
    var key = y + "-" + pad2(month + 1) + "-" + pad2(d);
    if (!yearText && key < todayKey) {
        key = (y + 1) + "-" + pad2(month + 1) + "-" + pad2(d);
    }
    return key;
}

// Date rules: [regex source (after the leading boundary), (match, todayKey) -> day key | null]
var DATE_RULES = [
    ["(day after tomorrow|öbür gün|yarından sonra)", function (m, today) { return DateUtil.addDaysKey(today, 2); }],
    ["(today|tonight|bugün|bu akşam)", function (m, today) { return today; }],
    ["(tomorrow|yarın)", function (m, today) { return DateUtil.addDaysKey(today, 1); }],
    ["(next week|gelecek hafta|önümüzdeki hafta)", function (m, today) { return DateUtil.quickDate(today, "nextweek"); }],
    ["(this weekend|weekend|hafta ?sonu)", function (m, today) { return DateUtil.quickDate(today, "weekend"); }],
    ["in (\\d{1,3}|an?|one) (days?|weeks?)", function (m, today) {
        var n = count(m[1]);
        return DateUtil.addDaysKey(today, /^w/i.test(m[2]) ? n * 7 : n);
    }],
    ["(\\d{1,3}|bir) (gün|hafta) sonra", function (m, today) {
        var n = count(m[1]);
        return DateUtil.addDaysKey(today, lower(m[2]) === "hafta" ? n * 7 : n);
    }],
    ["(?:on )?(next )?(" + WEEKDAYS_EN.join("|") + ")", function (m, today) {
        return nextWeekday(today, weekdayIndex(m[2]), !!m[1]);
    }],
    // "pazar" alone is also "market": only with "günü" or a qualifier
    ["(haftaya |gelecek |önümüzdeki |bu )?(pazartesi|salı|sali|çarşamba|carsamba|perşembe|persembe|cumartesi|cuma|pazar)( günü|y?[ae])?",
     function (m, today) {
        var name = lower(m[2]).replace("sali", "salı").replace("carsamba", "çarşamba").replace("persembe", "perşembe");
        var q = lower(m[1] || "").trim();
        if (name === "pazar" && !q && lower(m[3] || "").trim() !== "günü") {
            return null;
        }
        var wd = WEEKDAYS_TR.indexOf(name);
        if (q === "haftaya" || q === "gelecek" || q === "önümüzdeki") {
            return DateUtil.addDaysKey(DateUtil.quickDate(today, "nextweek"), (wd + 6) % 7);
        }
        return nextWeekday(today, wd, false);
    }],
    ["(?:on )?(\\d{1,2})(?:st|nd|rd|th)? (" + MONTH_RE + ")(?: (\\d{4}))?(?:['’]?[dt][ae])?", function (m, today) {
        return explicitDate(today, m[1], monthIndex(m[2]), m[3]);
    }],
    ["(?:on )?(" + MONTH_RE + ") (\\d{1,2})(?:st|nd|rd|th)?(?:,? (\\d{4}))?", function (m, today) {
        return explicitDate(today, m[2], monthIndex(m[1]), m[3]);
    }]
];

// Time rules: [regex source, match -> minutes | null]
var TIME_RULES = [
    ["(?:at )?(\\d{1,2})(?::(\\d{2}))? ?(am|pm)", function (m) {
        var h = parseInt(m[1], 10);
        if (h < 1 || h > 12) {
            return null;
        }
        h = h % 12 + (lower(m[3]) === "pm" ? 12 : 0);
        return h * 60 + (m[2] ? parseInt(m[2], 10) : 0);
    }],
    ["(?:at |saat )?(\\d{1,2}):(\\d{2})(?:['’]?[dt][ae])?", function (m) {
        return hm(m[1], m[2]);
    }],
    ["(?:at |saat )(\\d{1,2})(?:\\.(\\d{2}))?(?:['’]?[dt][ae])?", function (m) {
        return hm(m[1], m[2] || "0");
    }],
    ["(noon|öğlen|öğle)", function () { return 12 * 60; }]
];

function hm(h, mi) {
    var hh = parseInt(h, 10);
    var mm = parseInt(mi, 10);
    return hh < 24 && mm < 60 ? hh * 60 + mm : null;
}

var RECURRING_RE = new RegExp("(^|\\s)(every|everyday|daily|weekly|monthly|yearly|her (gün|hafta|ay|yıl|sabah|akşam|"
                              + WEEKDAYS_TR.join("|") + "|\\d+))" + END, "i");

// earliest, then longest match of any rule -> { value, start, end } | null
// A rule gets m.slice(1): [0] is the leading boundary, [1]… its own groups.
function firstMatch(text, rules, today) {
    var best = null;
    for (var r = 0; r < rules.length; r++) {
        var re = new RegExp("(^|\\s)" + rules[r][0] + END, "gi");
        var m;
        while ((m = re.exec(text)) !== null) {
            var start = m.index + m[1].length;
            var end = m.index + m[0].length;
            var value = rules[r][1](m.slice(1), today);
            if (value !== null && value !== undefined
                    && (!best || start < best.start || (start === best.start && end > best.end))) {
                best = { value: value, start: start, end: end };
            }
            if (re.lastIndex === m.index) {
                re.lastIndex++;
            }
        }
    }
    return best;
}

function parseDate(text, todayKey, nowMinutes) {
    if (!DateUtil.splitDateKey(todayKey) || RECURRING_RE.test(text)) {
        return null;
    }
    var d = firstMatch(text, DATE_RULES, todayKey);
    var t = firstMatch(text, TIME_RULES, todayKey);
    if (t && d && t.start < d.end && d.start < t.end) {
        t = null;                                  // overlapping: the date wins
    }
    if (!d && !t) {
        return null;
    }
    var key = d ? d.value : (t.value > nowMinutes ? todayKey : DateUtil.addDaysKey(todayKey, 1));
    var spans = [];
    if (d) {
        spans.push([d.start, d.end]);
    }
    if (t) {
        spans.push([t.start, t.end]);
    }
    spans.sort(function (a, b) { return a[0] - b[0]; });
    return { key: key, minutes: t ? t.value : null, spans: spans };
}

function findProject(text, projects) {
    var re = /(^|\s)#/g;
    var m;
    var found = null;
    while ((m = re.exec(text)) !== null) {
        var at = m.index + m[0].length;
        var rest = lower(text.slice(at));
        var best = null;
        for (var i = 0; i < (projects || []).length; i++) {
            var name = lower(projects[i].name);
            var after = rest.charAt(name.length);
            if (name && rest.indexOf(name) === 0 && (after === "" || /\s/.test(after))
                    && (!best || name.length > best.name.length)) {
                best = projects[i];
            }
        }
        var word = text.slice(at).split(/\s/)[0];
        if (best) {
            found = { name: best.name, id: best.id, color: best.color || "", known: true,
                      start: at - 1, end: at + best.name.length };
        } else if (word) {
            found = { name: word, id: "", color: "", known: false, start: at - 1, end: at + word.length };
        }
    }
    return found;
}

function findLabels(text, labels) {
    var out = [];
    var re = /(^|\s)@([^\s@#]+)/g;
    var m;
    while ((m = re.exec(text)) !== null) {
        var name = m[2];
        var known = null;
        for (var i = 0; i < (labels || []).length; i++) {
            if (lower(labels[i].name) === lower(name)) {
                known = labels[i];
            }
        }
        out.push(known ? { name: known.name, color: known.color || "", known: true } : { name: name, color: "", known: false });
    }
    return out;
}

function findPriority(text) {
    var re = new RegExp("(^|\\s)p([1-4])" + END, "gi");
    var m;
    var p = 0;
    while ((m = re.exec(text)) !== null) {
        p = parseInt(m[2], 10);
    }
    return p;
}

// Suggestions for the "#project" or "@label" being typed at the cursor (names may contain spaces).
// -> { kind: "project" | "label", start, end, query, items: [{ id, name, color }] } | null
// start..end is the text to replace (from the # or @ up to the cursor).
var MAX_SUGGESTIONS = 6;

function completion(text, cursor, projects, labels) {
    var s = String(text || "");
    var c = typeof cursor === "number" ? Math.min(Math.max(cursor, 0), s.length) : s.length;
    var before = s.slice(0, c);
    var at = Math.max(before.lastIndexOf("#"), before.lastIndexOf("@"));
    if (at < 0 || (at > 0 && !/\s/.test(before.charAt(at - 1)))) {
        return null;
    }
    var after = s.charAt(c);
    if (after !== "" && !/\s/.test(after)) {
        return null;                                // the cursor is inside a word
    }
    var kind = before.charAt(at) === "#" ? "project" : "label";
    var query = before.slice(at + 1);
    var q = lower(query);
    var pool = kind === "project" ? (projects || []) : (labels || []);
    var starts = [];
    var contains = [];
    for (var i = 0; i < pool.length; i++) {
        var name = String(pool[i].name || "");
        var n = lower(name);
        var item = { id: pool[i].id || "", name: name, color: pool[i].color || "" };
        if (n.indexOf(q) === 0) {
            starts.push(item);
        } else if (q !== "" && n.indexOf(q) > 0) {
            contains.push(item);
        }
    }
    var byName = function (a, b) { return lower(a.name) < lower(b.name) ? -1 : (lower(a.name) > lower(b.name) ? 1 : 0); };
    var items = starts.sort(byName).concat(contains.sort(byName)).slice(0, MAX_SUGGESTIONS);
    // a space ends the token unless it continues a longer name ("#Work Tr…" for "Work Trips")
    if (/\s/.test(query) && !starts.length) {
        return null;
    }
    // already complete and nothing longer to offer
    if (items.length === 1 && lower(items[0].name) === q) {
        return null;
    }
    return items.length ? { kind: kind, start: at, end: c, query: query, items: items } : null;
}

// The text with a suggestion accepted -> { text, cursor }
function applyCompletion(text, comp, item) {
    var s = String(text || "");
    var token = (comp.kind === "project" ? "#" : "@") + item.name + " ";
    var rest = s.slice(comp.end).replace(/^\s+/, "");
    return { text: s.slice(0, comp.start) + token + rest, cursor: comp.start + token.length };
}

function parse(text, opts) {
    var s = String(text || "");
    var o = opts || {};
    var project = findProject(s, o.projects);
    var date = parseDate(s, o.todayKey, typeof o.nowMinutes === "number" ? o.nowMinutes : 0);
    // words inside a project's name ("#Ev Yarın") are not a date
    if (date && project && project.known && date.spans.some(function (sp) { return sp[0] < project.end && project.start < sp[1]; })) {
        date = null;
    }
    return {
        date: date,
        recurring: RECURRING_RE.test(s),
        project: project,
        labels: findLabels(s, o.labels),
        priority: findPriority(s)
    };
}

// The text without the recognised date and time.
function stripSpans(text, spans) {
    var s = String(text || "");
    var list = (spans || []).slice().sort(function (a, b) { return b[0] - a[0]; });
    for (var i = 0; i < list.length; i++) {
        s = s.slice(0, list[i][0]) + s.slice(list[i][1]);
    }
    return s.replace(/\s+/g, " ").trim();
}

// Day key, or "YYYY-MM-DDTHH:MM:00" with a time: the value ContextRules applies as the due date.
function dueValue(date) {
    if (!date) {
        return "";
    }
    return date.minutes === null ? date.key : date.key + "T" + DateUtil.minutesToHHMM(date.minutes) + ":00";
}
