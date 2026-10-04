#!/usr/bin/env bash
# Extracts i18n strings from QML/JS into translations/template.pot and merges them into *.po.
set -euo pipefail
cd "$(dirname "$0")/.."

ID=$(node -e 'process.stdout.write(require("./package/metadata.json").KPlugin.Id)')
VERSION=$(node -e 'process.stdout.write(require("./package/metadata.json").KPlugin.Version)')
DOMAIN="plasma_applet_${ID}"

# logic/*.js is UI-text free by design (lib code returns codes, QML translates)
mapfile -t FILES < <(find package/contents -name '*.qml' | LC_ALL=C sort)

xgettext \
    --from-code=UTF-8 -C -kde \
    -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    --package-name="${DOMAIN}" --package-version="${VERSION}" \
    --msgid-bugs-address="https://github.com/bahadirdemircioglu/today/issues" \
    --no-location --sort-output \
    -o translations/template.pot "${FILES[@]}"
# keep the header stable between runs (no timestamp churn in git)
sed -i '/^"POT-Creation-Date:/d' translations/template.pot

for po in translations/*.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --update --backup=none --no-location --sort-output "$po" translations/template.pot
done
echo "Extracted $(grep -c '^msgid ' translations/template.pot) messages into translations/template.pot (domain ${DOMAIN})"
node scripts/i18n-catalogs.mjs
