# Todoist Today

Your Todoist **Today** view on the KDE Plasma 6 desktop and panel: overdue tasks first, then today's, timed tasks in time order. Complete tasks with one click and add new ones with Todoist's natural language. Works offline.

> Unofficial. Not created by, affiliated with, or supported by Doist.

- **Panel:** an icon with a count badge (red when something is overdue). Click it to open the list.
- **Desktop, small:** a big count and your next task.
- **Desktop, large / popup:** the full list with round, priority-coloured check circles, a completion animation, a "New task" field and an "All done for today" state.
- **Follows your Plasma theme:** light/dark, accent colour, font size and animation speed. No hard-coded colours.
- **Offline-first:** tasks are cached, and completions/additions made offline are queued. The queue survives Plasma restarts and is sent once you are back online.
- **Sync:** every 5 minutes, when you open the popup or hover the desktop widget (if the data is older than 30 s), and about a second after you complete or add something.

## Install

**From a release:** download `todoist-today-<version>.plasmoid` from [Releases](https://github.com/bahadirdemircioglu/today/releases), then either

- right-click the desktop → *Enter Edit Mode* → *Add Widgets…* → *Get New Widgets* → *Install Widget From Local File…*, or
- run `kpackagetool6 -t Plasma/Applet -i todoist-today-<version>.plasmoid` (use `-u` to upgrade).

**From source:**

```sh
kpackagetool6 -t Plasma/Applet -i package     # first install
kpackagetool6 -t Plasma/Applet -u package     # update
```

Requires Plasma 6.0 or newer. There is nothing to compile.

## Connect your account

1. Add the widget, then click **Open Todoist settings**. This opens *Settings → Integrations → Developer* in Todoist.
2. Copy your **API token** and paste it into the widget. It is checked right away and shows "Connected as *your name*".

You can also connect, or disconnect, from the widget's *Configure…* window. If you use the widget both in a panel and on the desktop, paste the token in each.

## Adding tasks

Whatever you type goes to Todoist's [Quick Add](https://todoist.com/help/articles/use-task-quick-add-in-todoist-va4Lhpzz), so the usual syntax works:

| You type | Result |
|---|---|
| `Call mom today p1` | due today, priority 1 |
| `Dentist tomorrow 3pm #Personal` | due tomorrow 15:00 in *Personal* (you'll see "Added to Personal · tomorrow 3pm") |
| `Pay rent every 1st @home` | recurring, labelled |
| `Buy milk // two litres` | due today (no date given), with a description |

A task without a date is scheduled for **today**, like in Todoist's own Today view. Dates are parsed in the language your Todoist account uses. English always works; Todoist's date parser may not support every language (for example Turkish), while `#project`, `@label` and `p1`–`p4` work in any language.

## Security

- Your API token is stored **unencrypted** in your Plasma config file (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`), readable by your user account. This is a deliberate trade-off: the widget is pure QML, so it cannot use KWallet. If the token leaks, reset it in Todoist's developer settings; the widget will ask for the new one.
- The token is never logged and never shown in tooltips or error messages.
- The widget talks only to `https://api.todoist.com`. Task text is always rendered as plain text, and Markdown links are reduced to their label.
- The task cache and offline queue live in `~/.local/share/plasmashell/QML/OfflineStorage/Databases/` (SQLite).

## Known limitations

- **Time zones:** "today" follows your Todoist time zone. When your computer is in a *different* time zone than your Todoist account, a fixed-time-zone task can shift by an hour across a daylight-saving boundary (rarely enough to move it to another day), and the day can switch up to 5 minutes late at a DST change. When both zones match, which is the normal case, this does not apply.
- **Offline Quick Add:** if the connection drops right after a new task was sent, the widget can't know whether Todoist created it. After the next sync it looks for a matching new task before sending it again. If no match is found, a duplicate is possible, though rare.
- Sub-tasks due today are shown as plain rows, without hierarchy. Editing, rescheduling, deleting and reordering are not supported. Use Todoist for those.

## Troubleshooting

- Logs: `journalctl --user -f -t plasmashell | grep todoist-today`. Running `plasmoidviewer -a package` prints them to the terminal.
- After updating the package, restart Plasma if the old version keeps showing: `systemctl --user restart plasma-plasmashell`.
- "Todoist didn't accept your token": the token was reset or revoked. Paste the current one from Todoist's settings.

## Development

```sh
npm test                                   # Node ≥ 20, zero dependencies
plasmoidviewer -a package                  # desktop form factor
plasmoidviewer -a package -l bottomedge -f horizontal   # panel
LANGUAGE=tr LANG=tr_TR.UTF-8 plasmoidviewer -a package  # Turkish UI (run scripts/i18n-build.sh first)
scripts/i18n-extract.sh                    # update translations/template.pot and *.po
scripts/i18n-build.sh                      # compile .mo files into package/contents/locale
scripts/package.sh                         # dist/todoist-today-<version>.plasmoid
```

All decision logic is plain JavaScript in `package/contents/ui/logic/` (`.pragma library` files, no QML or network dependencies), unit-tested in Node via `tests/helpers/load-qml-js.mjs`:

| File | Role |
|---|---|
| `DateUtil.js` | time-zone offsets, day keys, Todoist `due` parsing |
| `TaskStore.js` | merging `/sync` responses, computing and ordering the Today list |
| `CommandQueue.js` | the persistent offline queue (`item_close` commands, Quick Adds) |
| `SyncMachine.js` | the sync state machine: debouncing, retries/backoff, recovery, account checks |
| `TodoistClient.js` | HTTP via `XMLHttpRequest` and response classification |
| `ModelSync.js` | minimal `ListModel` updates so only changed rows animate |
| `Storage.js` | LocalStorage persistence (QML-only, not unit-tested) |

`SyncController.qml` only executes the effects `SyncMachine` returns. The architecture plan is in [`docs/architecture/todoist-today-plan.md`](docs/architecture/todoist-today-plan.md), including the manual acceptance checklist (M1–M23) for a real Plasma session.

Releases: bump `Version` in `package/metadata.json` and `package.json`, add a CHANGELOG section, then push a `vX.Y.Z` tag. CI builds the `.plasmoid` and attaches it to a GitHub Release.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
