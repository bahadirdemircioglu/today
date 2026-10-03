.pragma library

// Which timed tasks should raise a notification now. Pure: the caller passes the rows, the clock
// and what was already shown; it records the returned keys (shared across widget instances so a
// panel and a desktop widget never notify twice).
//
// rows: today's rows ({ id, title, dateKey, minutes }) from TaskStore.computeToday().today
// leadMinutes: notify this long before the task's time (0 = at the time, < 0 = off)
// sent: { "<key>": true }   snoozed: { "<key>": untilMs }
// -> [{ key, baseKey, id, title, minutes, snoozed }]  (baseKey: the task's key, used to snooze again)

var LATE_GRACE_MINUTES = 15;   // after a restart, don't notify for tasks long past
var SNOOZE_MINUTES = 10;

function keyFor(row) {
    return row.id + "|" + row.dateKey + "|" + row.minutes;
}

function due(rows, todayKey, nowMinutes, nowMs, leadMinutes, sent, snoozed) {
    var out = [];
    var s = sent || {};
    var z = snoozed || {};
    for (var k in z) {
        if (Object.prototype.hasOwnProperty.call(z, k) && nowMs >= z[k]) {
            var parts = k.split("|");
            for (var j = 0; j < rows.length; j++) {
                if (rows[j].id === parts[0]) {
                    out.push({ key: k + "|" + z[k], baseKey: k, id: rows[j].id, title: rows[j].title, minutes: rows[j].minutes, snoozed: true });
                    break;
                }
            }
        }
    }
    if (leadMinutes < 0) {
        return out;
    }
    for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        if (r.dateKey !== todayKey || r.minutes === null || r.minutes === undefined) {
            continue;
        }
        var key = keyFor(r);
        if (s[key] || Object.prototype.hasOwnProperty.call(z, key)) {
            continue;
        }
        if (nowMinutes >= r.minutes - leadMinutes && nowMinutes <= r.minutes + LATE_GRACE_MINUTES) {
            out.push({ key: key, baseKey: key, id: r.id, title: r.title, minutes: r.minutes, snoozed: false });
        }
    }
    return out;
}

// Keeps only today's keys so the shared record stays small.
function prune(sent, todayKey) {
    var out = {};
    for (var k in sent) {
        if (Object.prototype.hasOwnProperty.call(sent, k) && k.indexOf("|" + todayKey + "|") >= 0) {
            out[k] = true;
        }
    }
    return out;
}
