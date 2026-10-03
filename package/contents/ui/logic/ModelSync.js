.pragma library

// Brings a ListModel-like object (count, get(i), insert(i, obj), move(from, to, n), set(i, obj),
// remove(i)) in line with `rows` (each row has a unique `key`) using minimal operations,
// so ListView add/remove/displaced transitions animate only what actually changed.

function indexOfKey(model, key, from) {
    for (var i = from; i < model.count; i++) {
        if (model.get(i).key === key) {
            return i;
        }
    }
    return -1;
}

function sameRow(a, b) {
    for (var k in b) {
        if (Object.prototype.hasOwnProperty.call(b, k) && a[k] !== b[k]) {
            return false;
        }
    }
    return true;
}

function sync(model, rows) {
    var wanted = {};
    var i;
    for (i = 0; i < rows.length; i++) {
        wanted[rows[i].key] = true;
    }
    for (i = model.count - 1; i >= 0; i--) {
        if (!wanted[model.get(i).key]) {
            model.remove(i);
        }
    }
    for (i = 0; i < rows.length; i++) {
        var row = rows[i];
        var j = indexOfKey(model, row.key, i);
        if (j < 0) {
            model.insert(i, row);
            continue;
        }
        if (j !== i) {
            model.move(j, i, 1);
        }
        if (!sameRow(model.get(i), row)) {
            model.set(i, row);
        }
    }
}
