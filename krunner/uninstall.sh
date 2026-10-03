#!/usr/bin/env bash
set -euo pipefail
data="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -rf "$data/todoist-plasma-runner"
rm -f "$data/krunner/dbusplugins/todoist-plasma-runner.desktop" \
      "$data/dbus-1/services/io.github.bahadirdemircioglu.TodoistRunner.service"
kquitapp6 krunner >/dev/null 2>&1 || true
echo "Removed the Todoist KRunner runner."
