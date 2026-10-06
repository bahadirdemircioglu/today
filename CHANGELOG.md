# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.2.2] - 2026-10-06

### Added
- Numeric dates in Quick Add, with an optional time glued on: "12/10/2026-15:00",
  "12.10.2026 15:00", "12.10", "2026-10-12T09:00", and the short "12-15:00" (the 12th of this
  month, or of the next month if it has passed). Day/month order unless the system writes
  month/day; "saat 12.10" is still a time.

## [2.2.1] - 2026-10-05

### Added
- Quick Add suggests projects after "#" and labels after "@" as you type (also names with
  spaces, and names that only contain what you typed). Tab or Enter completes, ↑↓ choose,
  Esc closes the list. The "no such project" warning only shows once nothing matches.

### Changed
- A project picked with "#name" is applied by its id instead of being left to Todoist's parser,
  so names with spaces or non-English letters always work. A project name is never read as a date.

## [2.2.0] - 2026-10-04

### Added
- Live Quick Add preview: under "New task", the date and time, project (in its colour, or a
  warning when it doesn't exist), labels and priority as they will be applied.
- Dates in English and Turkish are recognised by the widget itself ("yarın saat 15", "cuma",
  "haftaya salı", "3 gün sonra", "tomorrow 3pm", "in 3 days", "12 dec"), so they work whatever
  language the Todoist account uses. Click the date in the preview to keep the words instead.
- "Reschedule" on the Overdue header: moves all overdue tasks to today, tomorrow, the weekend or
  next week, keeping their times, with undo. Recurring tasks are left as they are.
- "New project…" under Projects in the list title menu: name, Todoist colour and an optional
  parent project. The widget switches to the new project right away; offline it is queued
  with a temporary id and gets its real id on the next sync. Hitting the Todoist plan's
  project limit shows a clear message.
- Language setting (Settings → Language): System default, English or Türkçe. Switching takes
  effect at once, including day and month names; it applies to all widgets of this kind.
- "Pick date & time…" in the task menu (and the T key): quick choices, a month calendar, an
  optional time, "No date", or a schedule typed the Todoist way ("next friday 3pm",
  "every monday 9am"). Recurring tasks can now be rescheduled by typing a new schedule.
- Project and label colours from Todoist: a coloured "#" before the project name and coloured
  "@labels", like on the web.

### Changed
- The task menu moved from T to M on the keyboard (T now picks the date, as in Todoist).
- Smaller "+" buttons on Upcoming day headers.
- Translations are now built into the widget (`logic/Catalogs.js`, generated from
  `translations/*.po`), so they work without compiling `.mo` files.

## [2.1.0] - 2026-10-03

### Added
- Reminders: Plasma notifications before timed tasks (configurable lead time) with Complete and
  "Remind me in 10 minutes"; panel and desktop widgets never notify twice.
- Undo for completions (4 seconds), like deletions.
- Keyboard navigation in the list, and the widget's global shortcut focuses New task.
- Daily goal ring (Todoist productivity stats) in the Today header and the small desktop view.
- Custom filter query in the settings, shown as its own list.
- Fold sub-tasks in project lists; full task descriptions on click or from the task menu.
- Deadlines shown under tasks.
- Other widget instances offer the already connected account in their setup screen.
- Background can be switched off in edit mode.
- Optional KRunner plugin (`krunner/`): `todo <text>` adds a task, `todo ?<word>` finds one.

### Changed
- The settings category is now "General".

## [2.0.0] - 2026-10-03

Renamed to **Todoist for Plasma** (new plugin id `io.github.bahadirdemircioglu.todoistplasma`):
remove the 1.x widget and add the new one.

### Added
- Lists beyond Today: Inbox, Upcoming (7 days, day by day), projects (sections, indented
  sub-tasks), labels and saved filters (evaluated by Todoist, last results kept offline).
- List switcher in the title with task counts; "Start here in this widget" pins a list per widget.
- New tasks land in the list they were added from (date, project, label); "+" on an Upcoming day.
- Task menu (right click or the ⋯ button): edit title in place, reschedule (today, tomorrow,
  this weekend, next week), priority, move to project, copy link, open in Todoist, and delete
  with a 5-second undo. All changes are queued offline like completions.
- Labels and the first description line are shown under a task.
- Settings: panel badge source (Today, current list, none) and unpinning.

### Changed
- All open tasks are cached (not only dated ones); the cache schema moves to v2 and is rebuilt
  with one full sync.
- Tasks added from the Today list without a date are scheduled for today instead of silently
  landing in the Inbox.

## [1.0.0] - 2026-10-03

### Added
- Todoist "Today" view for Plasma 6: overdue tasks first, then today's, timed tasks ordered by time,
  untimed ones in Todoist's day order.
- Size-aware layout: panel icon with a count badge, a small desktop view (count + next task), and a
  full list with round priority-coloured check circles and a completion animation.
- Completing tasks (`item_close`: recurring tasks move to their next date).
- Adding tasks through Todoist Quick Add (natural-language dates, `#project`, `@label`, `p1`–`p4`).
- Incremental sync via Todoist API v1 `/sync`; refresh on popup open, on hover over the desktop
  widget, after your own changes, every 5 minutes and at midnight.
- Persistent offline cache and action queue (idempotent commands, retries with backoff, rate-limit
  handling, recovery from rejected batches).
- One-screen setup with instant token check, plus an Account page in the settings window.
- Turkish translation.
