import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const I18n = loadQmlJs("I18n.js");
const { CATALOGS } = loadQmlJs("Catalogs.js");

const CAT = {
  tr: {
    plural: (n) => Number(n > 1),
    messages: {
      "Today": "Bugün",
      "Added to %1": "%1 içine eklendi",
      "day header\u0004Today · %1": "Bugün · %1",
      "%1 task": ["%1 görev", "%1 görev"],
    },
  },
};

test("pickLanguage: explicit choice, system languages, fallback to English", () => {
  assert.equal(I18n.pickLanguage("tr", ["en-US"], ["tr"]), "tr");
  assert.equal(I18n.pickLanguage("en", ["tr-TR"], ["tr"]), "en");
  assert.equal(I18n.pickLanguage("de", ["tr-TR"], ["tr"]), "en");
  assert.equal(I18n.pickLanguage("", ["tr-TR", "en-US"], ["tr"]), "tr");
  assert.equal(I18n.pickLanguage("", ["tr_TR.UTF-8"], ["tr"]), "tr");
  assert.equal(I18n.pickLanguage("", ["de-DE", "en-GB", "tr"], ["tr"]), "en");
  assert.equal(I18n.pickLanguage("", ["de-DE"], ["tr"]), "en");
  assert.equal(I18n.pickLanguage("", [], ["tr"]), "en");
});

test("translate: catalog lookup, context, placeholders, fallback to the source text", () => {
  assert.equal(I18n.translate(CAT, "tr", "", "Today", []), "Bugün");
  assert.equal(I18n.translate(CAT, "tr", "", "Added to %1", ["Ev"]), "Ev içine eklendi");
  assert.equal(I18n.translate(CAT, "tr", "day header", "Today · %1", ["Pazartesi"]), "Bugün · Pazartesi");
  assert.equal(I18n.translate(CAT, "tr", "", "Not translated %1", ["x"]), "Not translated x");
  assert.equal(I18n.translate(CAT, "en", "", "Added to %1", ["Home"]), "Added to Home");
  assert.equal(I18n.translate(CAT, "tr", "", "%1 and %2", ["a"]), "a and %2");
});

test("translatePlural: count is %1, later arguments shift to %2", () => {
  assert.equal(I18n.translatePlural(CAT, "en", "", "%1 task", "%1 tasks", 1, []), "1 task");
  assert.equal(I18n.translatePlural(CAT, "en", "", "%1 task", "%1 tasks", 3, []), "3 tasks");
  assert.equal(I18n.translatePlural(CAT, "tr", "", "%1 task", "%1 tasks", 3, []), "3 görev");
  assert.equal(I18n.translatePlural(CAT, "en", "", "%2 · %1 overdue", "%2 · %1 overdue", 2, ["Today"]), "Today · 2 overdue");
});

test("generated catalogs: Turkish is complete and keeps every placeholder", () => {
  const tr = CATALOGS.tr;
  assert.ok(tr, "Catalogs.js has Turkish");
  const pot = fs.readFileSync(new URL("../translations/template.pot", import.meta.url), "utf8");
  const potCount = (pot.match(/^msgid "/gm) || []).length - 1; // minus the header
  assert.equal(Object.keys(tr.messages).length, potCount);
  for (const [key, value] of Object.entries(tr.messages)) {
    const msgid = key.split("\u0004").pop();
    const want = new Set(msgid.match(/%\d/g) || []);
    // a plural form may add the count (%1) that the singular source leaves out
    if (Array.isArray(value)) want.add("%1");
    for (const form of [].concat(value)) {
      for (const ph of form.match(/%\d/g) || []) {
        assert.ok(want.has(ph), `${key} -> ${form}: unexpected ${ph}`);
      }
      if (!Array.isArray(value)) {
        assert.deepEqual(new Set(form.match(/%\d/g) || []), want, `${key} -> ${form}`);
      }
    }
  }
  assert.equal(tr.plural(1), 0);
  assert.equal(tr.plural(2), 1);
});
