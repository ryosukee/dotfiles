"""Deterministic checks for the Codex adapter to Claude Code rules."""

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/.local/bin/codex-claude-rules"
loader = importlib.machinery.SourceFileLoader("codex_claude_rules", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
rules = importlib.util.module_from_spec(spec)
loader.exec_module(rules)


class RuleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo"
        self.cwd = self.repo / "projects" / "app"
        self.cwd.mkdir(parents=True)
        self.target = self.cwd / "docs" / "planning" / "a.md"
        self.target.parent.mkdir(parents=True)
        self.target.write_text("test", encoding="utf-8")
        self.home_patch = patch.object(rules.Path, "home", return_value=self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)
        self.state_patch = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.home / "state")})
        self.state_patch.start()
        self.addCleanup(self.state_patch.stop)

    def add_rule(self, base, name, paths, body):
        source = base / ".claude" / "rules" / name
        source.parent.mkdir(parents=True, exist_ok=True)
        header = "---\npaths:\n" + "".join(f'  - "{pattern}"\n' for pattern in paths) + "---\n" if paths else ""
        source.write_text(header + body + "\n", encoding="utf-8")
        return source

    def event(self, kind, **extra):
        return {"hook_event_name": kind, "session_id": "test-session", "cwd": str(self.cwd), **extra}

    def invoke(self, event):
        output = StringIO()
        with redirect_stdout(output):
            rules.run(event)
        return json.loads(output.getvalue()) if output.getvalue() else None

    def test_parent_and_child_rules_match_their_own_base(self):
        self.add_rule(self.repo, "root.md", ["projects/*/docs/planning/**"], "root rule")
        self.add_rule(self.cwd, "app.md", ["docs/**"], "app rule")
        result = list(rules.matching_rules(self.cwd, self.target))
        self.assertEqual([body.strip() for _, body in result], ["root rule", "app rule"])

    def test_nested_and_global_always_rules(self):
        self.add_rule(self.home, "user.md", [], "user rule")
        self.add_rule(self.repo, "root.md", [], "root rule")
        self.add_rule(self.cwd, "app.md", ["docs/**"], "conditional rule")
        result = self.invoke(self.event("SessionStart", source="startup"))
        context = result["hookSpecificOutput"]["additionalContext"]
        self.assertIn("user rule", context)
        self.assertIn("root rule", context)
        self.assertNotIn("conditional rule", context)

    def test_pre_tool_use_delivers_once_and_resets_after_compact(self):
        self.add_rule(self.repo, "root.md", ["projects/*/docs/planning/**"], "root rule")
        event = self.event("PreToolUse", tool_name="Bash", tool_input={"command": "sed -n '1,20p' docs/planning/a.md"})
        self.assertIn("root rule", self.invoke(event)["hookSpecificOutput"]["additionalContext"])
        self.assertIsNone(self.invoke(event))
        self.invoke(self.event("SessionStart", source="compact"))
        self.assertIn("root rule", self.invoke(event)["hookSpecificOutput"]["additionalContext"])

    def test_apply_patch_and_glob_zero_depth(self):
        self.add_rule(self.cwd, "markdown.md", ["**/*.md"], "markdown rule")
        event = self.event("PreToolUse", tool_name="apply_patch", tool_input={"command": "*** Begin Patch\n*** Update File: README.md\n*** End Patch"})
        self.assertIn("markdown rule", self.invoke(event)["hookSpecificOutput"]["additionalContext"])

    def test_nonmatching_rule_is_not_injected(self):
        self.add_rule(self.repo, "other.md", ["as-is/**"], "wrong rule")
        event = self.event("PreToolUse", tool_name="Bash", tool_input={"command": "sed docs/planning/a.md"})
        self.assertIsNone(self.invoke(event))

    def test_brace_expansion(self):
        pattern = rules.glob_regex("src/**/*.{ts,tsx}")
        self.assertTrue(pattern.fullmatch("src/index.ts"))
        self.assertTrue(pattern.fullmatch("src/components/button.tsx"))
        self.assertFalse(pattern.fullmatch("src/components/button.md"))

    def test_session_end_removes_state(self):
        self.add_rule(self.repo, "root.md", [], "root rule")
        self.invoke(self.event("SessionStart", source="startup"))
        self.assertTrue(rules.state_path("test-session").exists())
        self.invoke(self.event("SessionEnd"))
        self.assertFalse(rules.state_path("test-session").exists())


if __name__ == "__main__":
    unittest.main()
