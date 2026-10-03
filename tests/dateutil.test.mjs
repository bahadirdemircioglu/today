import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const D = loadQmlJs("DateUtil.js");

test("#1 parseGmtOffset basic forms", () => {
  assert.equal(D.parseGmtOffset("+03:00"), 180);
  assert.equal(D.parseGmtOffset("-03:30"), -210);
  assert.equal(D.parseGmtOffset("garbage"), null);
  assert.equal(D.parseGmtOffset(undefined), null);
});

test("#1b parseGmtOffset tolerates prefixes and compact forms", () => {
  assert.equal(D.parseGmtOffset("GMT+03:00"), 180);
  assert.equal(D.parseGmtOffset("UTC-03:30"), -210);
  assert.equal(D.parseGmtOffset("+0300"), 180);
  assert.equal(D.parseGmtOffset("+3"), 180);
  assert.equal(D.parseGmtOffset("+25:00"), null);
});

test("#1c tzInfoOffset prefers numeric hours/minutes", () => {
  assert.equal(D.tzInfoOffset({ hours: -3, minutes: 0, gmt_string: "x" }), -180);
  assert.equal(D.tzInfoOffset({ hours: 5, minutes: 30 }), 330);
  assert.equal(D.tzInfoOffset({ hours: 0, minutes: 30, gmt_string: "-00:30" }), -30);
  assert.equal(D.tzInfoOffset({ gmt_string: "+01:00" }), 60);
  assert.equal(D.tzInfoOffset(null), null);
});

test("#2 dayKeyAt crosses midnight with the offset", () => {
  assert.equal(D.dayKeyAt(Date.UTC(2026, 9, 3, 21, 30), 180), "2026-10-04");
  assert.equal(D.dayKeyAt(Date.UTC(2026, 9, 3, 20, 59), () => 180), "2026-10-03");
});

test("#3 full-day due", () => {
  assert.deepEqual(D.parseDue({ date: "2026-10-03" }, 180), { dateKey: "2026-10-03", minutes: null, isRecurring: false });
});

test("#4/#5 floating due keeps wall-clock time", () => {
  const expected = { dateKey: "2026-10-03", minutes: 900, isRecurring: false };
  assert.deepEqual(D.parseDue({ date: "2026-10-03T15:00:00" }, 0), expected);
  assert.deepEqual(D.parseDue({ date: "2026-10-03T15:00:00.000000" }, -600), expected);
});

test("#6 fixed-zone due is converted into the reference zone", () => {
  assert.deepEqual(
    D.parseDue({ date: "2026-10-03T22:30:00.000000Z", timezone: "Europe/Madrid" }, () => 180),
    { dateKey: "2026-10-04", minutes: 90, isRecurring: false });
});

test("#6b followSystem uses the offset valid at the task's own instant (DST)", () => {
  const sys = (ms) => (new Date(ms).getUTCMonth() >= 3 && new Date(ms).getUTCMonth() <= 9 ? 180 : 120);
  const offsetAt = D.makeOffsetFn({ gmtOffsetMin: 180, followSystem: true }, sys);
  assert.deepEqual(D.parseDue({ date: "2027-01-10T22:30:00Z", timezone: "Europe/Athens" }, offsetAt),
    { dateKey: "2027-01-11", minutes: 30, isRecurring: false });
});

test("#7 null / unparsable due", () => {
  assert.equal(D.parseDue(null, 0), null);
  assert.equal(D.parseDue({ date: "x" }, 0), null);
  assert.equal(D.parseDue({ date: "2026-02-30" }, 0), null);
  assert.equal(D.parseDue({ date: "2026-10-03T25:00:00" }, 0), null);
});

test("#8 makeOffsetFn", () => {
  const t = Date.UTC(2026, 9, 3);
  assert.equal(D.makeOffsetFn({ gmtOffsetMin: 180, followSystem: true }, () => 120)(t), 120);
  assert.equal(D.makeOffsetFn({ gmtOffsetMin: 180, followSystem: false }, () => 120)(t), 180);
  assert.equal(D.makeOffsetFn(null, () => 120)(t), 120);
});

test("#9 recurring flag is carried", () => {
  assert.equal(D.parseDue({ date: "2026-10-03", is_recurring: true }, 0).isRecurring, true);
  assert.equal(D.parseDue({ date: "2026-10-03", isRecurring: true }, 0).isRecurring, true);
});

test("parseIsoUtc handles 6 fractional digits and offsets", () => {
  assert.equal(D.parseIsoUtc("2026-10-03T09:00:00.123456Z"), Date.UTC(2026, 9, 3, 9, 0, 0, 123));
  assert.equal(D.parseIsoUtc("2026-10-03T12:00:00+03:00"), Date.UTC(2026, 9, 3, 9));
  assert.equal(D.parseIsoUtc("2026-10-03T09:00:00"), Date.UTC(2026, 9, 3, 9));
  assert.equal(D.parseIsoUtc("nope"), null);
});

test("minutesOfDayAt and daysBetween", () => {
  assert.equal(D.minutesOfDayAt(Date.UTC(2026, 9, 3, 9, 15), 180), 735);
  assert.equal(D.daysBetween("2026-09-30", "2026-10-03"), 3);
});
