#!/usr/bin/env python3
"""KRunner D-Bus runner for Todoist (companion of the Todoist for Plasma widget).

  todo <text>   -> add <text> with Todoist Quick Add (dates, #project, @label, p1 ...)
  todo ?<word>  -> find open tasks; Enter opens one in Todoist, the action completes it

Needs python3-dbus and python3-gobject. Installed by krunner/install.sh.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

import todoist_runner_core as core

BUS_NAME = "io.github.bahadirdemircioglu.TodoistRunner"
OBJECT_PATH = "/runner"
IFACE = "org.kde.krunner1"
API = "https://api.todoist.com/api/v1"
TIMEOUT = 4


def api(method, path, token, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def notify(summary, body=""):
    try:
        bus = dbus.SessionBus()
        obj = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
        dbus.Interface(obj, "org.freedesktop.Notifications").Notify(
            "Todoist", 0, "view-calendar-tasks", summary, body, [], {}, 4000)
    except dbus.DBusException:
        pass


class Runner(dbus.service.Object):
    def __init__(self):
        dbus.service.Object.__init__(self, dbus.service.BusName(BUS_NAME, dbus.SessionBus()), OBJECT_PATH)
        self._search_cache = {}

    def _token(self):
        return core.find_token()

    @dbus.service.method(IFACE, in_signature="s", out_signature="a(sssida{sv})")
    def Match(self, query):
        parsed = core.parse_query(query)
        if parsed is None:
            return []
        kind, arg = parsed
        if kind == "add":
            match_id, text, subtext, relevance = core.add_match(arg)
            return [(match_id, text, "list-add", 100, relevance, {"subtext": subtext})]
        token = self._token()
        if not token:
            return [("setup", "Todoist: no API token found", "dialog-warning", 10, 0.5,
                     {"subtext": "Connect the Todoist for Plasma widget, or set TODOIST_TOKEN"})]
        tasks = self._search_cache.get(arg)
        if tasks is None:
            try:
                q = urllib.parse.quote("search: " + arg)
                tasks = core.tasks_from_response(api("GET", "/tasks/filter?query=" + q + "&limit=20", token))
            except (urllib.error.URLError, ValueError, OSError):
                tasks = []
            self._search_cache = {arg: tasks}
        out = []
        for task in tasks:
            m = core.task_match(task, arg)
            if m:
                match_id, text, subtext, relevance = m
                out.append((match_id, text, "view-calendar-tasks", 70, relevance, {"subtext": subtext}))
        return out

    @dbus.service.method(IFACE, out_signature="a(sss)")
    def Actions(self):
        return [("complete", "Complete task", "checkmark")]

    @dbus.service.method(IFACE, in_signature="ss")
    def Run(self, match_id, action_id):
        token = self._token()
        if match_id.startswith("add:"):
            if not token:
                notify("Todoist: no API token found", "Connect the Todoist for Plasma widget first.")
                return
            text = match_id[4:]
            try:
                api("POST", "/tasks/quick", token, {"text": text, "meta": False})
                notify("Added to Todoist", text)
            except (urllib.error.URLError, OSError) as e:
                notify("Couldn't add the task", str(e))
            return
        if match_id.startswith("task:"):
            task_id = match_id[5:]
            if action_id == "complete" and token:
                try:
                    api("POST", "/tasks/%s/close" % task_id, token)
                    self._search_cache = {}
                    notify("Completed in Todoist")
                except (urllib.error.URLError, OSError) as e:
                    notify("Couldn't complete the task", str(e))
            else:
                subprocess.Popen(["xdg-open", core.TASK_URL + task_id])

    @dbus.service.method(IFACE)
    def Teardown(self):
        self._search_cache = {}


def main():
    DBusGMainLoop(set_as_default=True)
    Runner()
    GLib.MainLoop().run()


if __name__ == "__main__":
    sys.exit(main())
