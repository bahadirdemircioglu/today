.pragma library

.import "DateUtil.js" as DateUtil

// Changes that touch several tasks at once.

// Moves overdue tasks to targetKey, keeping their time of day. Recurring tasks are left alone:
// a plain date would end their recurrence.
// rows: TaskStore rows ({ id, minutes, isRecurring }). -> { changes: [{ itemId, due }], skipped }
function rescheduleOverdue(rows, targetKey) {
    var changes = [];
    var skipped = 0;
    if (!DateUtil.splitDateKey(targetKey)) {
        return { changes: changes, skipped: 0 };
    }
    for (var i = 0; i < (rows || []).length; i++) {
        var r = rows[i];
        if (r.isRecurring) {
            skipped++;
            continue;
        }
        var due = DateUtil.composeDue(targetKey, DateUtil.minutesToHHMM(r.minutes));
        if (due) {
            changes.push({ itemId: r.id, due: due });
        }
    }
    return { changes: changes, skipped: skipped };
}
