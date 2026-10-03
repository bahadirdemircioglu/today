// Loads a QML ".pragma library" JS file in Node without changing production code:
// ".pragma" / ".import" lines are blanked (line numbers stay intact for stack traces),
// relative ".import "X.js" as X" dependencies are loaded the same way and injected by name,
// and the top-level `function` / `var` declarations are returned as the module namespace.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
export const LOGIC_DIR = path.resolve(here, "../../package/contents/ui/logic");

const DIRECTIVE_RE = /^\s*\.(pragma|import)\b/;
const JS_IMPORT_RE = /^\s*\.import\s+"([^"]+\.js)"\s+as\s+(\w+)/;

export function stripDirectives(src) {
  return src.split("\n").map((l) => (DIRECTIVE_RE.test(l) ? "" : l)).join("\n");
}

function topLevelNames(src) {
  const names = new Set();
  for (const line of src.split("\n")) {
    const m = /^(?:function\s+(\w+)|var\s+(\w+))/.exec(line);
    if (m) names.add(m[1] || m[2]);
  }
  return [...names];
}

/**
 * @param {string} relPath file relative to baseDir (default: package/contents/ui/logic)
 * @param {{deps?: Record<string,string>, globals?: Record<string, unknown>, baseDir?: string}} opts
 */
export function loadQmlJs(relPath, opts = {}) {
  const baseDir = opts.baseDir || LOGIC_DIR;
  const globals = opts.globals || {};
  const file = path.resolve(baseDir, relPath);
  const src = fs.readFileSync(file, "utf8");

  const deps = {};
  for (const line of src.split("\n")) {
    const m = JS_IMPORT_RE.exec(line);
    if (m) deps[m[2]] = m[1];
  }
  Object.assign(deps, opts.deps || {});

  const injected = {};
  for (const [name, depPath] of Object.entries(deps)) {
    injected[name] = loadQmlJs(depPath, { baseDir: path.dirname(file), globals });
  }
  for (const [name, value] of Object.entries(globals)) injected[name] = value;

  const names = topLevelNames(src);
  const body = stripDirectives(src) +
    "\n;return {" + names.map((n) => `${JSON.stringify(n)}: typeof ${n} === "undefined" ? undefined : ${n}`).join(",") + "};";
  const params = Object.keys(injected);
  const fn = vm.compileFunction(body, params, { filename: file });
  return fn(...params.map((p) => injected[p]));
}
