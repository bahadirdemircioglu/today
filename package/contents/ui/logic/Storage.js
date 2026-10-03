.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

// QML-only persistence (SQLite via QtQuick.LocalStorage). Not loaded in Node tests.
// Rows are keyed by applet id so two widget instances never share a queue.

var DB_NAME = "TodoistToday";
var db = null;

function open() {
    if (db !== null) {
        return db;
    }
    db = Sql.LocalStorage.openDatabaseSync(DB_NAME, "", "Todoist Today cache", 5 * 1024 * 1024);
    db.transaction(function (tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS kv ("
                      + "applet_id TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, "
                      + "updated_at INTEGER NOT NULL, PRIMARY KEY (applet_id, key))");
    });
    return db;
}

// -> string | null
function load(appletId, key) {
    var value = null;
    try {
        open().readTransaction(function (tx) {
            var rs = tx.executeSql("SELECT value FROM kv WHERE applet_id = ? AND key = ?", [appletId, key]);
            if (rs.rows.length > 0) {
                value = rs.rows.item(0).value;
            }
        });
    } catch (e) {
        console.warn("[todoist-today] storage load failed:", e);
    }
    return value;
}

function save(appletId, key, value) {
    try {
        open().transaction(function (tx) {
            tx.executeSql("INSERT OR REPLACE INTO kv (applet_id, key, value, updated_at) VALUES (?, ?, ?, ?)",
                          [appletId, key, value, Date.now()]);
        });
        return true;
    } catch (e) {
        console.warn("[todoist-today] storage save failed:", e);
        return false;
    }
}

function clear(appletId) {
    try {
        open().transaction(function (tx) {
            tx.executeSql("DELETE FROM kv WHERE applet_id = ?", [appletId]);
        });
    } catch (e) {
        console.warn("[todoist-today] storage clear failed:", e);
    }
}
