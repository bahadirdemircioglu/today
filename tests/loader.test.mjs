import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const fixtures = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures/qmljs");

test("loads a .pragma library file and exposes top-level functions and vars", () => {
  const ctx = loadQmlJs("Plain.js", { baseDir: fixtures });
  assert.equal(ctx.f(), 1);
  assert.equal(ctx.ANSWER, 42);
});

test(".import dependencies are injected by name (auto-detected and explicit)", () => {
  assert.equal(loadQmlJs("UsesDep.js", { baseDir: fixtures }).callDep(), "dep");
  assert.equal(loadQmlJs("UsesDep.js", { baseDir: fixtures, deps: { Dep: "Dep.js" } }).callDep(), "dep");
});

test("stack traces keep the original line numbers", () => {
  const ctx = loadQmlJs("Throws.js", { baseDir: fixtures });
  try {
    ctx.boom();
    assert.fail("expected throw");
  } catch (e) {
    assert.match(e.stack, /Throws\.js:5/);
  }
});

test("globals are visible inside the library", () => {
  class Fake {}
  const ctx = loadQmlJs("UsesXhr.js", { baseDir: fixtures, globals: { XMLHttpRequest: Fake } });
  assert.ok(ctx.make() instanceof Fake);
});
