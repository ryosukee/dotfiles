"""Checks for the independent required-plugin SessionStart hook."""

import importlib.util
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "codex/.codex/scripts/check-required-plugins.py"
spec = importlib.util.spec_from_file_location("check_required_plugins", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class RequiredPluginTests(unittest.TestCase):
    def test_all_marketplace_plugins_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / "marketplace.json"
            catalog.write_text(json.dumps({
                "name": "settings",
                "plugins": [{"name": "rules"}, {"name": "editor"}],
            }), encoding="utf-8")
            self.assertEqual(
                checker.required_plugin_ids(catalog),
                ["editor@settings", "rules@settings"],
            )

    def test_missing_and_disabled_plugins_are_reported(self):
        required = ["rules@settings", "editor@settings", "docs@settings"]
        listing = {"installed": [
            {"pluginId": "rules@settings", "installed": True, "enabled": True},
            {"pluginId": "editor@settings", "installed": True, "enabled": False},
        ]}
        self.assertEqual(
            checker.missing_plugin_ids(required, listing),
            ["editor@settings", "docs@settings"],
        )

    def test_session_start_emits_warning_only_for_missing_plugins(self):
        listing = {"installed": []}
        completed = type("Result", (), {"stdout": json.dumps(listing)})()
        with patch.object(checker, "required_plugin_ids", return_value=["rules@settings"]), \
                patch.object(checker.subprocess, "run", return_value=completed), \
                patch.object(checker.sys, "stdin", StringIO('{"hook_event_name":"SessionStart"}')):
            output = StringIO()
            with redirect_stdout(output):
                self.assertEqual(checker.main(), 0)
        self.assertIn("rules@settings", json.loads(output.getvalue())["systemMessage"])

    def test_non_session_event_does_not_call_codex(self):
        with patch.object(checker.sys, "stdin", StringIO('{"hook_event_name":"PreToolUse"}')), \
                patch.object(checker.subprocess, "run") as run:
            output = StringIO()
            with redirect_stdout(output):
                self.assertEqual(checker.main(), 0)
        run.assert_not_called()
        self.assertEqual(output.getvalue(), "")
