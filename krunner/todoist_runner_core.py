"""Pure helpers for the Todoist KRunner runner (no D-Bus, no network): unit-tested."""
import configparser
import os
import re

PLUGIN_ID = "io.github.bahadirdemircioglu.todoistplasma"
TRIGGERS = ("todo", "td")
APPLETSRC = "~/.config/plasma-org.kde.plasma.desktop-appletsrc"
RUNNER_RC = "~/.config/todoist-plasma-runnerrc"
TASK_URL = "https://app.todoist.com/app/task/"
_ID_RE = re.compile(r"^[A-Za-z0-9]+$")


def parse_query(query):
    """'todo Buy milk tomorrow' -> ('add', 'Buy milk tomorrow');
    'todo ?milk' -> ('search', 'milk'); anything else -> None."""
    q = (query or "").strip()
    for trigger in TRIGGERS:
        if q.lower().startswith(trigger + " "):
            rest = q[len(trigger) + 1:].strip()
            if not rest:
                return None
            if rest.startswith("?"):
                term = rest[1:].strip()
                return ("search", term) if term else None
            return ("add", rest)
    return None


def _token_from_runner_rc(path):
    p = os.path.expanduser(path)
    if not os.path.exists(p):
        return None
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(p, encoding="utf-8")
    token = cp.get("General", "token", fallback="").strip()
    return token or None


def token_from_appletsrc(text):
    """Finds the apiToken of the first Todoist for Plasma widget in a Plasma appletsrc file.
    Groups look like [Containments][1][Applets][23] (plugin=...) and
    [Containments][1][Applets][23][Configuration][General] (apiToken=...)."""
    plugin_groups = set()
    tokens = {}
    group = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            group = line
            continue
        if group is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if key == "plugin" and value == PLUGIN_ID:
            plugin_groups.add(group)
        elif key == "apiToken" and value and group.endswith("[Configuration][General]"):
            tokens[group[: -len("[Configuration][General]")]] = value
    for g in sorted(plugin_groups):
        if g in tokens:
            return tokens[g]
    return None


def find_token(env=None, runner_rc=RUNNER_RC, appletsrc=APPLETSRC):
    """TODOIST_TOKEN env var, then ~/.config/todoist-plasma-runnerrc [General] token=,
    then the token of a Todoist for Plasma widget."""
    env = os.environ if env is None else env
    token = (env.get("TODOIST_TOKEN") or "").strip()
    if token:
        return token
    token = _token_from_runner_rc(runner_rc)
    if token:
        return token
    p = os.path.expanduser(appletsrc)
    if os.path.exists(p):
        with open(p, encoding="utf-8", errors="replace") as f:
            return token_from_appletsrc(f.read())
    return None


def plain_title(content):
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", content or "")
    s = re.sub(r"(\*\*|__|~~)(.+?)\1", r"\2", s)
    return re.sub(r"\s+", " ", s).strip()


def tasks_from_response(json_value):
    """GET /tasks/filter returns {results: [...], next_cursor} (a plain list is accepted too)."""
    if isinstance(json_value, list):
        return json_value
    if isinstance(json_value, dict) and isinstance(json_value.get("results"), list):
        return json_value["results"]
    return []


def task_match(task, term):
    """-> (match_id, text, subtext, relevance) for a task, or None if its id is unusable."""
    task_id = str(task.get("id", ""))
    if not _ID_RE.match(task_id):
        return None
    title = plain_title(task.get("content", ""))
    due = (task.get("due") or {}).get("string") or ""
    subtext = "Todoist" + (" · " + due if due else "")
    relevance = 0.9 if term.lower() in title.lower() else 0.6
    return ("task:" + task_id, title, subtext, relevance)


def add_match(text):
    return ("add:" + text, 'Add to Todoist: "%s"' % text, "Todoist Quick Add: dates, #project, @label, p1", 1.0)
