#!/usr/bin/env bash
# Builds dist/todoist-today-<Version>.plasmoid (zip of package/ contents, metadata.json at the root).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(node -e 'process.stdout.write(require("./package/metadata.json").KPlugin.Version)')
OUT="dist/todoist-today-${VERSION}.plasmoid"

scripts/i18n-build.sh
mkdir -p dist
rm -f "$OUT"
(cd package && zip -qr "../${OUT}" . -x '*.swp' -x '*~')
echo "Packaged ${OUT}"
