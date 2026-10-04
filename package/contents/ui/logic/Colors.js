.pragma library

// Todoist's named colours (projects, labels, filters) -> hex, as listed in the API v1 docs.
var TODOIST = {
    berry_red: "#b8255f", red: "#dc4c3e", orange: "#c77100", yellow: "#b29104",
    olive_green: "#949c31", lime_green: "#65a33a", green: "#369307", mint_green: "#42a393",
    teal: "#148fad", sky_blue: "#319dc0", light_blue: "#6988a4", blue: "#4180ff",
    grape: "#692ec2", violet: "#ca3fee", lavender: "#a4698c", magenta: "#e05095",
    salmon: "#c9766f", charcoal: "#808080", grey: "#999999", taupe: "#8f7a69"
};

// name (or an already-hex value) -> "#rrggbb", or "" when unknown
function hex(name) {
    if (typeof name !== "string" || !name) {
        return "";
    }
    if (/^#[0-9a-fA-F]{6}$/.test(name)) {
        return name.toLowerCase();
    }
    return Object.prototype.hasOwnProperty.call(TODOIST, name) ? TODOIST[name] : "";
}
