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
  assert.deepEqual(JSON.parse(JSON.stringify(r.project)), { name: "Work Trips", id: "p2", color: "red", known: true, start: 11, end: 22 });
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

test("completion: projects and labels at the cursor, names with spaces", () => {
  const P = opts.projects;
  const L = [{ name: "errand", color: "green" }, { name: "evening", color: "" }];
  const c1 = QP.completion("Book hotel #wo", 14, P, L);
  assert.equal(c1.kind, "project");
  assert.deepEqual(c1.items.map((i) => i.name), ["Work", "Work Trips"]);
  assert.deepEqual([c1.start, c1.end], [11, 14]);
  assert.deepEqual(QP.completion("x #Work Tr", 10, P, L).items.map((i) => i.name), ["Work Trips"]);
  assert.deepEqual(QP.completion("x #", 3, P, L).items.map((i) => i.name), ["Ev", "Work", "Work Trips"]);
  assert.deepEqual(QP.completion("x @e", 4, P, L).items.map((i) => i.name), ["errand", "evening"]);
  assert.deepEqual(QP.completion("x #rip", 6, P, L).items.map((i) => i.name), ["Work Trips"]); // contains
  assert.equal(QP.completion("x #Ev", 5, P, L), null);            // complete, nothing longer
  assert.equal(QP.completion("x #zz", 5, P, L), null);
  assert.equal(QP.completion("x #wo then", 10, P, L), null);       // token already ended
  assert.equal(QP.completion("mail#wo", 7, P, L), null);           // not at a word start
  assert.equal(QP.completion("x #wo", 4, P, L), null);             // cursor inside the word
});

test("applyCompletion inserts the full name and a space", () => {
  const text = "Book hotel #wo tomorrow";
  const c = QP.completion(text, 14, opts.projects, []);
  const r = QP.applyCompletion(text, c, c.items[1]);
  assert.equal(r.text, "Book hotel #Work Trips tomorrow");
  assert.equal(r.cursor, "Book hotel #Work Trips ".length);
});

test("project span, and a project name is not read as a date", () => {
  const P = opts.projects.concat([{ id: "p9", name: "Ev Yarın", color: "" }]);
  const r = QP.parse("Boya #Ev Yarın", { ...opts, projects: P });
  assert.equal(r.project.id, "p9");
  assert.deepEqual([r.project.start, r.project.end], [5, 14]);
  assert.equal(r.date, null);
  const r2 = QP.parse("Boya #Ev yarın", opts);
  assert.equal(r2.project.id, "p3");
  assert.equal(QP.dueValue(r2.date), "2026-10-05");
  assert.equal(QP.stripSpans("Boya #Ev yarın", r2.date.spans.concat([[r2.project.start, r2.project.end]])), "Boya");
});

test("numeric dates, with a time glued on", () => {
  assert.equal(date("Toplantı 12/10/2026-15:00"), "2026-10-12T15:00:00");
  assert.equal(date("Toplantı 12.10.2026 15:00"), "2026-10-12T15:00:00");
  assert.equal(date("Toplantı 12-15:00"), "2026-10-12T15:00:00");
  assert.equal(date("Toplantı 3-09:30"), "2026-11-03T09:30:00");     // the 3rd has passed: next month
  assert.equal(date("Fatura 12.10"), "2026-10-12");
  assert.equal(date("Fatura 1/2"), "2027-02-01");                      // past this year: next year
  assert.equal(date("Fatura 12.10.26 14.30"), "2026-10-12T14:30:00");
  assert.equal(date("Fatura 2026-10-12T09:00"), "2026-10-12T09:00:00");
  assert.equal(date("Oku 12/10 15:00"), "2026-10-12T15:00:00");
  assert.equal(date("Ara saat 12.10"), "2026-10-04T12:10:00");         // "saat" makes it a time
  assert.equal(date("x 31/02"), null);
  assert.equal(date("x 12/10-25:00"), null);
  assert.equal(date("v1.2 sürümü"), null);
  const us = QP.parse("x 10/12", { ...opts, monthFirst: true }).date;
  assert.equal(QP.dueValue(us), "2026-10-12");
  const t = "Toplantı 12/10/2026-15:00 #Ev";
  assert.equal(QP.stripSpans(t, QP.parse(t, opts).date.spans), "Toplantı #Ev");
});
