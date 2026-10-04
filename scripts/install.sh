#!/usr/bin/env bash
# Installs the widget from this checkout, or upgrades it if it is already installed.
# Also removes the old 1.x "Todoist Today" package (different plugin id) if present.
set -euo pipefail
cd "$(dirname "$0")/.."

ID=$(node -e 'process.stdout.write(require("./package/metadata.json").KPlugin.Id)' 2>/dev/null \
     || sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' package/metadata.json)
OLD_ID="io.github.bahadirdemircioglu.todoisttoday"

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$OLD_ID"; then
    echo "Removing the old 1.x widget ($OLD_ID)…"
    kpackagetool6 -t Plasma/Applet -r "$OLD_ID"
fi

if [ -x scripts/i18n-build.sh ] && command -v msgfmt >/dev/null; then
    scripts/i18n-build.sh >/dev/null
fi

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$ID"; then
    kpackagetool6 -t Plasma/Applet -u package
    echo "Upgraded $ID."
else
    kpackagetool6 -t Plasma/Applet -i package
    echo "Installed $ID. Add \"Todoist for Plasma\" from Add Widgets."
fi
echo "If Plasma still shows the old version: systemctl --user restart plasma-plasmashell"
