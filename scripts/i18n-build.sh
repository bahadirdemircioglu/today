#!/usr/bin/env bash
# Compiles translations/*.po into package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<Id>.mo
set -euo pipefail
cd "$(dirname "$0")/.."

ID=$(node -e 'process.stdout.write(require("./package/metadata.json").KPlugin.Id)')
DOMAIN="plasma_applet_${ID}"

rm -rf package/contents/locale
for po in translations/*.po; do
    [ -e "$po" ] || continue
    lang=$(basename "$po" .po)
    out="package/contents/locale/${lang}/LC_MESSAGES"
    mkdir -p "$out"
    msgfmt --check -o "${out}/${DOMAIN}.mo" "$po"
    echo "Built ${out}/${DOMAIN}.mo"
done
