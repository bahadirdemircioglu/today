#!/usr/bin/env bash
# Installs the optional Todoist KRunner runner for the current user (no root needed).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/todoist-plasma-runner"

python3 -c 'import dbus, gi' 2>/dev/null || {
    echo "Missing python3-dbus / python3-gobject (Arch: python-dbus python-gobject; Debian/Ubuntu: python3-dbus python3-gi)." >&2
    exit 1
}

mkdir -p "$dest" "$data/krunner/dbusplugins" "$data/dbus-1/services"
install -m 0755 "$here/todoist_runner.py" "$dest/todoist_runner.py"
install -m 0644 "$here/todoist_runner_core.py" "$dest/todoist_runner_core.py"
install -m 0644 "$here/todoist-plasma-runner.desktop" "$data/krunner/dbusplugins/todoist-plasma-runner.desktop"
cat > "$data/dbus-1/services/io.github.bahadirdemircioglu.TodoistRunner.service" <<SERVICE
[D-BUS Service]
Name=io.github.bahadirdemircioglu.TodoistRunner
Exec=/usr/bin/env python3 $dest/todoist_runner.py
SERVICE

# make KRunner pick the new runner up
kquitapp6 krunner >/dev/null 2>&1 || true
echo "Installed. In KRunner (Alt+Space) type: todo Buy milk tomorrow   or   todo ?milk"
