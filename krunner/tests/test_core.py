import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import todoist_runner_core as core  # noqa: E402

APPLETSRC = """
[Containments][1][Applets][7]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][1][Applets][7][Configuration][General]
apiToken=not-ours

[Containments][1][Applets][23]
immutability=1
plugin=io.github.bahadirdemircioglu.todoistplasma

[Containments][1][Applets][23][Configuration][General]
accountName=Ada
apiToken=0123456789abcdef
"""


class ParseQuery(unittest.TestCase):
    def test_add_and_search(self):
        self.assertEqual(core.parse_query("todo Buy milk tomorrow"), ("add", "Buy milk tomorrow"))
        self.assertEqual(core.parse_query("TD call mom p1"), ("add", "call mom p1"))
        self.assertEqual(core.parse_query("todo ?milk"), ("search", "milk"))
        self.assertEqual(core.parse_query("todo ? milk "), ("search", "milk"))

    def test_not_ours(self):
        for q in ["", "todo", "todo ", "todo ?", "todolist", "firefox", "buy milk"]:
            self.assertIsNone(core.parse_query(q), q)


class Token(unittest.TestCase):
    def test_appletsrc_picks_our_widget(self):
        self.assertEqual(core.token_from_appletsrc(APPLETSRC), "0123456789abcdef")
        self.assertIsNone(core.token_from_appletsrc("[Containments][1][Applets][7]\nplugin=x\n"))

    def test_precedence(self):
        with tempfile.TemporaryDirectory() as d:
            rc = os.path.join(d, "runnerrc")
            src = os.path.join(d, "appletsrc")
            with open(src, "w") as f:
                f.write(APPLETSRC)
            self.assertEqual(core.find_token({}, rc, src), "0123456789abcdef")
            with open(rc, "w") as f:
                f.write("[General]\ntoken=from-rc\n")
            self.assertEqual(core.find_token({}, rc, src), "from-rc")
            self.assertEqual(core.find_token({"TODOIST_TOKEN": "env"}, rc, src), "env")
            self.assertIsNone(core.find_token({}, os.path.join(d, "x"), os.path.join(d, "y")))


class Matches(unittest.TestCase):
    def test_task_match(self):
        task = {"id": "6X7rM8997g3RQmvh", "content": "Buy **oat** milk", "due": {"string": "tomorrow"}}
        self.assertEqual(core.task_match(task, "milk"),
                         ("task:6X7rM8997g3RQmvh", "Buy oat milk", "Todoist · tomorrow", 0.9))
        self.assertIsNone(core.task_match({"id": "../x", "content": "x"}, "x"))

    def test_responses_and_add(self):
        self.assertEqual(core.tasks_from_response({"results": [{"id": "1"}]}), [{"id": "1"}])
        self.assertEqual(core.tasks_from_response([{"id": "2"}]), [{"id": "2"}])
        self.assertEqual(core.tasks_from_response(None), [])
        self.assertEqual(core.add_match("milk")[0], "add:milk")


if __name__ == "__main__":
    unittest.main()
