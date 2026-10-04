import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const QP = loadQmlJs("QuickParse.js");

// Sunday 4 October 2026, 10:00
const TODAY = "2026-10-04";
const opts = {
  todayKey: TODAY,
  nowMinutes: 600,
  projects: [{ id: "p1", name: "Work", color: "blue" }, { id: "p2", name: "Work Trips", color: "red" }, { id: "p3", name: "Ev", color: "" }],
  labels: [{ name: "errand", color: "green" }],
};
const date = (text) => {
  const d = QP.parse(text, opts).date;
  return d ? QP.dueValue(d) : null;
};

test("English dates and times", () => {
  assert.equal(date("Dentist today"), "2026-10-04");
  assert.equal(date("Dentist tomorrow 3pm"), "2026-10-05T15:00:00");
  assert.equal(date("Call at 9:30pm"), "2026-10-04T21:30:00");
  assert.equal(date("Pay rent day after tomorrow"), "2026-10-06");
  assert.equal(date("Report friday"), "2026-10-09");
  assert.equal(date("Report next sunday"), "2026-10-11");
  assert.equal(date("Report sunday"), "2026-10-04");
  assert.equal(date("Plan next week"), "2026-10-05");
  assert.equal(date("Hike this weekend"), "2026-10-10");
  assert.equal(date("Renew in 3 days"), "2026-10-07");
  assert.equal(date("Renew in a week"), "2026-10-11");
  assert.equal(date("Party on 12 Dec"), "2026-12-12");
  assert.equal(date("Party Dec 12th at 20:00"), "2026-12-12T20:00:00");
  assert.equal(date("Taxes 1 april"), "2027-04-01");
  assert.equal(date("Meeting 9:00"), "2026-10-05T09:00:00"); // already past today
  assert.equal(date("Meeting 15:00"), "2026-10-04T15:00:00");
});

test("Turkish dates and times", () => {
  assert.equal(date("Diş hekimi yarın saat 15"), "2026-10-05T15:00:00");
  assert.equal(date("Fatura Yarın 14:30'da"), "2026-10-05T14:30:00");
  assert.equal(date("Toplantı bugün"), "2026-10-04");
  assert.equal(date("SSK ödemesi cuma"), "2026-10-09");
  assert.equal(date("Rapor cumartesi"), "2026-10-10");
  assert.equal(date("Rapor pazartesiye"), "2026-10-05");
  assert.equal(date("Rapor haftaya salı"), "2026-10-06");   // Sunday: next week starts tomorrow
  assert.equal(date("Rapor bu salı"), "2026-10-06");
  assert.equal(date("Kira 3 gün sonra"), "2026-10-07");
  assert.equal(date("Kira bir hafta sonra"), "2026-10-11");
  assert.equal(date("Tatil hafta sonu"), "2026-10-10");
  assert.equal(date("Doğum günü 5 kasım"), "2026-11-05");
  assert.equal(date("Vergi 30 nisan 2027"), "2027-04-30");
  assert.equal(date("Öbür gün ara"), "2026-10-06");
  assert.equal(date("Pazar günü yürüyüş"), "2026-10-04");
});

test("no false dates", () => {
  assert.equal(date("Pazar alışverişi"), null);       // "pazar" = market
  assert.equal(date("Buy milk"), null);
  assert.equal(date("Read #Tomorrow notes"), null);
  assert.equal(date("Call her tomorrow"), "2026-10-05");   // English "her" is not "every"
  assert.equal(date("30 şubat"), null);
});

test("recurring schedules are left to Todoist", () => {
  const r = QP.parse("Water plants every day", opts);
  assert.equal(r.recurring, true);
  assert.equal(r.date, null);
  assert.equal(QP.parse("Spor her sabah", opts).recurring, true);
  assert.equal(QP.parse("Call her", opts).recurring, false);
});

test("projects, labels, priority", () => {
  const r = QP.parse("Book hotel #Work Trips @errand @new p2", opts);
  assert.deepEqual(JSON.parse(JSON.stringify(r.project)), { name: "Work Trips", id: "p2", color: "red", known: true });
  assert.deepEqual(JSON.parse(JSON.stringify(r.labels)), [
    { name: "errand", color: "green", known: true },
    { name: "new", color: "", known: false },
  ]);
  assert.equal(r.priority, 2);
  assert.equal(QP.parse("x #work", opts).project.id, "p1");
  assert.equal(QP.parse("x #Nope", opts).project.known, false);
  assert.equal(QP.parse("email p5", opts).priority, 0);
});

test("stripSpans removes the date and time only", () => {
  const text = "Diş hekimi yarın saat 15 #Ev";
  const d = QP.parse(text, opts).date;
  assert.equal(QP.stripSpans(text, d.spans), "Diş hekimi #Ev");
  const t2 = "Dentist tomorrow at 3pm p1";
  assert.equal(QP.stripSpans(t2, QP.parse(t2, opts).date.spans), "Dentist p1");
});
