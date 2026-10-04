.pragma library

// Pure date/time helpers. No Intl, no IANA tz database (QV4 has neither):
// everything works with minute offsets supplied by an `offsetAt(ms)` function.

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// "+03:00", "-03:30", "GMT+03:00", "UTC-3", "+0300", "+3" -> minutes; anything else -> null
function parseGmtOffset(str) {
    if (typeof str !== "string") {
        return null;
    }
    var s = str.trim().replace(/^(GMT|UTC)\s*/i, "");
    var m = /^([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(s);
    if (!m) {
        return null;
    }
    var h = parseInt(m[2], 10);
    var mi = m[3] ? parseInt(m[3], 10) : 0;
    if (h > 14 || mi > 59) {
        return null;
    }
    var total = h * 60 + mi;
    return m[1] === "-" ? -total : total;
}

// Todoist user.tz_info -> minutes. Numeric hours/minutes win over gmt_string.
function tzInfoOffset(tzInfo) {
    if (!tzInfo) {
        return null;
    }
    if (typeof tzInfo.hours === "number" && !isNaN(tzInfo.hours)) {
        var minutes = typeof tzInfo.minutes === "number" ? Math.abs(tzInfo.minutes) : 0;
        var negative = tzInfo.hours < 0
            || (tzInfo.hours === 0 && typeof tzInfo.gmt_string === "string"
                && tzInfo.gmt_string.trim().replace(/^(GMT|UTC)\s*/i, "").charAt(0) === "-");
        var total = Math.abs(tzInfo.hours) * 60 + minutes;
        return negative ? -total : total;
    }
    return parseGmtOffset(tzInfo.gmt_string);
}

// Offset of the machine's own time zone at a given instant (DST-aware via Date).
function systemOffsetAt(ms) {
    return -new Date(ms).getTimezoneOffset();
}

// tz: store.tz ({ gmtOffsetMin, followSystem }) or null.
// Returns offsetAt(ms) -> minutes east of UTC.
function makeOffsetFn(tz, sysOffsetAtFn) {
    var sys = sysOffsetAtFn || systemOffsetAt;
    if (!tz || tz.followSystem || typeof tz.gmtOffsetMin !== "number") {
        return function (ms) { return sys(ms); };
    }
    var fixed = tz.gmtOffsetMin;
    return function () { return fixed; };
}

function offsetOf(offsetAt, ms) {
    if (typeof offsetAt === "function") {
        return offsetAt(ms);
    }
    return typeof offsetAt === "number" ? offsetAt : 0;
}

function keyFromShiftedDate(d) {
    return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate());
}

// "YYYY-MM-DD" of the instant `ms` in the reference time zone.
function dayKeyAt(ms, offsetAt) {
    return keyFromShiftedDate(new Date(ms + offsetOf(offsetAt, ms) * 60000));
}

// Minutes since local midnight of the instant `ms` in the reference time zone.
function minutesOfDayAt(ms, offsetAt) {
    var d = new Date(ms + offsetOf(offsetAt, ms) * 60000);
    return d.getUTCHours() * 60 + d.getUTCMinutes();
}

function validYmd(y, mo, d) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) {
        return false;
    }
    var probe = new Date(Date.UTC(y, mo - 1, d));
    return probe.getUTCMonth() === mo - 1 && probe.getUTCDate() === d;
}

var DUE_RE = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z)?)?$/;

// Todoist v1 `due` -> { dateKey, minutes|null, isRecurring } in the reference zone, or null.
// Three shapes live in `due.date`: full day, floating wall-clock time, fixed UTC ("...Z").
function parseDue(due, offsetAt) {
    if (!due || typeof due.date !== "string") {
        return null;
    }
    var m = DUE_RE.exec(due.date);
    if (!m) {
        return null;
    }
    var y = parseInt(m[1], 10);
    var mo = parseInt(m[2], 10);
    var d = parseInt(m[3], 10);
    if (!validYmd(y, mo, d)) {
        return null;
    }
    var isRecurring = !!(due.is_recurring || due.isRecurring);
    if (m[4] === undefined) {
        return { dateKey: m[1] + "-" + m[2] + "-" + m[3], minutes: null, isRecurring: isRecurring };
    }
    var h = parseInt(m[4], 10);
    var mi = parseInt(m[5], 10);
    if (h > 23 || mi > 59) {
        return null;
    }
    if (m[7] === undefined) {
        // floating: wall-clock time in whatever zone the user is in
        return { dateKey: m[1] + "-" + m[2] + "-" + m[3], minutes: h * 60 + mi, isRecurring: isRecurring };
    }
    var s = m[6] ? parseInt(m[6], 10) : 0;
    var utc = Date.UTC(y, mo - 1, d, h, mi, s);
    var shifted = new Date(utc + offsetOf(offsetAt, utc) * 60000);
    return {
        dateKey: keyFromShiftedDate(shifted),
        minutes: shifted.getUTCHours() * 60 + shifted.getUTCMinutes(),
        isRecurring: isRecurring
    };
}

var ISO_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:?\d{2})?$/;

// ISO-8601 timestamp (Todoist uses 6 fractional digits, which QV4's Date.parse may reject) -> ms or null.
// Strings without a zone are treated as UTC (Todoist's *_at fields are UTC).
function parseIsoUtc(str) {
    if (typeof str !== "string") {
        return null;
    }
    var m = ISO_RE.exec(str);
    if (!m) {
        return null;
    }
    var ms = m[7] ? Math.floor(parseInt((m[7] + "000").substr(0, 3), 10)) : 0;
    var t = Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10),
                     parseInt(m[4], 10), parseInt(m[5], 10), m[6] ? parseInt(m[6], 10) : 0, ms);
    if (m[8] && m[8] !== "Z") {
        var off = parseGmtOffset(m[8]);
        if (off === null) {
            return null;
        }
        t -= off * 60000;
    }
    return t;
}

// "YYYY-MM-DD" -> { y, m, d } (for building a local Date in QML for display)
function splitDateKey(key) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key || "");
    if (!m) {
        return null;
    }
    return { y: parseInt(m[1], 10), m: parseInt(m[2], 10), d: parseInt(m[3], 10) };
}

// Whole days between two day keys (b - a).
function daysBetween(aKey, bKey) {
    var a = splitDateKey(aKey);
    var b = splitDateKey(bKey);
    if (!a || !b) {
        return 0;
    }
    return Math.round((Date.UTC(b.y, b.m - 1, b.d) - Date.UTC(a.y, a.m - 1, a.d)) / 86400000);
}

function addDaysKey(key, n) {
    var p = splitDateKey(key);
    if (!p) {
        return key;
    }
    var d = new Date(Date.UTC(p.y, p.m - 1, p.d + n));
    return keyFromShiftedDate(d);
}

// 0 = Sunday ... 6 = Saturday
function weekdayOfKey(key) {
    var p = splitDateKey(key);
    return p ? new Date(Date.UTC(p.y, p.m - 1, p.d)).getUTCDay() : 0;
}

// Quick reschedule targets, as in Todoist's task menu.
// which: "today" | "tomorrow" | "weekend" (coming Saturday; on a weekend, next one) | "nextweek" (next Monday)
function quickDate(todayKey, which) {
    var wd = weekdayOfKey(todayKey);
    switch (which) {
    case "today":
        return todayKey;
    case "tomorrow":
        return addDaysKey(todayKey, 1);
    case "weekend":
        return addDaysKey(todayKey, wd === 6 ? 7 : 6 - wd);
    case "nextweek":
        return addDaysKey(todayKey, ((8 - wd) % 7) || 7);
    default:
        return null;
    }
}

// Lenient time input -> minutes since midnight, or null.
// "15:30", "15.30", "1530", "930", "9", "09:05" are all accepted.
function parseTimeInput(text) {
    var s = String(text === undefined || text === null ? "" : text).trim();
    if (!s) {
        return null;
    }
    var m = /^(\d{1,2})(?:[:.]?(\d{2}))?$/.exec(s);
    if (!m) {
        return null;
    }
    var h = parseInt(m[1], 10);
    var mi = m[2] ? parseInt(m[2], 10) : 0;
    if (s.length === 3 && !/[:.]/.test(s)) {      // "930" -> 9:30
        h = parseInt(s.charAt(0), 10);
        mi = parseInt(s.substr(1), 10);
    }
    if (h > 23 || mi > 59) {
        return null;
    }
    return h * 60 + mi;
}

// Due object for item_update from a day and an optional time ("" = all day).
// Times are floating (no zone), like dates typed in Todoist. -> { date } or null if the time is invalid.
function composeDue(dateKey, timeText) {
    if (!splitDateKey(dateKey)) {
        return null;
    }
    var t = String(timeText || "").trim();
    if (!t) {
        return { date: dateKey };
    }
    var minutes = parseTimeInput(t);
    if (minutes === null) {
        return null;
    }
    return { date: dateKey + "T" + pad2(Math.floor(minutes / 60)) + ":" + pad2(minutes % 60) + ":00" };
}

// "YYYY-MM-DD" for a local JS Date's calendar day (picker cells are local dates).
function keyOfLocalDate(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

// "HH:MM" from minutes, for prefilling the time field.
function minutesToHHMM(minutes) {
    if (minutes === null || minutes === undefined || minutes < 0) {
        return "";
    }
    return pad2(Math.floor(minutes / 60)) + ":" + pad2(minutes % 60);
}
