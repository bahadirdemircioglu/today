# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Task menu (right click or the ⋯ button): edit title in place, reschedule (today, tomorrow,
  this weekend, next week), priority, move to project, copy link, open in Todoist, and delete
  with a 5-second undo. All changes are queued offline like completions.

### Changed
- Tasks added from the widget without a date are now scheduled for today (as in Todoist's Today
  view) instead of silently landing in the Inbox and never appearing in the list.

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
