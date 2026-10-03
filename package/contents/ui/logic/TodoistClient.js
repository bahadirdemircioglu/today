.pragma library

// HTTP only (global XMLHttpRequest). Each call returns the XHR so the caller can abort() it;
// QML JS has no setTimeout, so the 15 s timeout is a Timer in SyncController.
// cb(result) with result = { kind, status, json, retryAfterSec }.
// The token is never logged or put into results.

var BASE_URL = "https://api.todoist.com/api/v1";
var RESOURCE_TYPES = ["items", "projects", "user", "user_item_orders"];
var DEFAULT_RATE_WAIT_SEC = 60;

function parseRetryAfter(header) {
    if (header === undefined || header === null) {
        return null;
    }
    var s = String(header).trim();
    if (!/^\d+$/.test(s)) {
        return null;
    }
    return parseInt(s, 10);
}

// status: HTTP status (0 = no response). json: parsed body or undefined. parseOk: body parsed.
// -> { kind: "ok"|"network"|"auth"|"rate"|"server"|"client", retryAfterSec }
function classify(status, json, retryAfterHeader, parseOk) {
    var extra = json && typeof json === "object" && json.error_extra ? json.error_extra : null;
    var headerSec = parseRetryAfter(retryAfterHeader);
    var bodySec = extra && typeof extra.retry_after === "number" ? extra.retry_after : null;
    if (status === 0) {
        return { kind: "network", retryAfterSec: null };
    }
    if (status >= 200 && status < 300) {
        return parseOk ? { kind: "ok", retryAfterSec: null } : { kind: "server", retryAfterSec: null };
    }
    if (status === 401 || status === 403) {
        return { kind: "auth", retryAfterSec: null };
    }
    if (status === 429) {
        return { kind: "rate", retryAfterSec: headerSec !== null ? headerSec : (bodySec !== null ? bodySec : DEFAULT_RATE_WAIT_SEC) };
    }
    if (status >= 500 && status < 600) {
        return { kind: "server", retryAfterSec: headerSec !== null ? headerSec : bodySec };
    }
    if (status >= 400 && status < 500) {
        return { kind: "client", retryAfterSec: null };
    }
    return { kind: "server", retryAfterSec: null };
}

function encodeForm(fields) {
    var parts = [];
    for (var k in fields) {
        if (Object.prototype.hasOwnProperty.call(fields, k)) {
            parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(fields[k]));
        }
    }
    return parts.join("&");
}

function request(method, path, token, body, contentType, cb) {
    var xhr = new XMLHttpRequest();
    var done = false;
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4 || done) {
            return;
        }
        done = true;
        var status = xhr.status || 0;
        var json;
        var parseOk = false;
        var text = xhr.responseText;
        if (text !== undefined && text !== null && text !== "") {
            try {
                json = JSON.parse(text);
                parseOk = true;
            } catch (e) {
                parseOk = false;
            }
        }
        var header = null;
        try {
            header = xhr.getResponseHeader("Retry-After");
        } catch (e2) {
            header = null;
        }
        var c = classify(status, json, header, parseOk);
        cb({ kind: c.kind, status: status, json: json, retryAfterSec: c.retryAfterSec });
    };
    xhr.open(method, BASE_URL + path);
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    if (contentType) {
        xhr.setRequestHeader("Content-Type", contentType);
    }
    xhr.send(body === undefined ? null : body);
    return xhr;
}

// params: { syncToken, commands: [] }
function sync(token, params, cb) {
    var fields = {
        sync_token: params && params.syncToken ? params.syncToken : "*",
        resource_types: JSON.stringify(RESOURCE_TYPES)
    };
    if (params && params.commands && params.commands.length) {
        fields.commands = JSON.stringify(params.commands);
    }
    return request("POST", "/sync", token, encodeForm(fields), "application/x-www-form-urlencoded", cb);
}

function getUser(token, cb) {
    return request("GET", "/user", token, null, null, cb);
}

function quickAdd(token, text, cb) {
    return request("POST", "/tasks/quick", token, JSON.stringify({ text: text, meta: false }), "application/json", cb);
}
