"""Black-box tests for the independent required-plugin SessionStart hook."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "stow/codex/.codex/scripts/check-required-plugins.sh"


class RequiredPluginTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.script = self.root / "stow/codex/.codex/scripts/check-required-plugins.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE, self.script)
        self.catalog = self.root / ".agents/plugins/marketplace.json"
        self.catalog.parent.mkdir(parents=True)
        self.set_catalog("settings", ["rules"])
        self.bin = self.root / "bin"
        self.bin.mkdir()
        jq = shutil.which("jq")
        if jq is None:
            self.skipTest("jq is required for the shell checker integration tests")
        (self.bin / "jq").symlink_to(jq)
        self.stub("python3", "exit 0")
        self.set_listing([])

    def set_catalog(self, name, plugins):
        self.catalog.write_text(json.dumps({
            "name": name,
            "plugins": [{"name": plugin} for plugin in plugins],
        }), encoding="utf-8")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
        path.chmod(0o755)

    def set_listing(self, plugins):
        listing = json.dumps({"installed": plugins})
        self.stub("codex", f"printf '%s\\n' {shlex.quote(listing)}")

    def run_hook(self, event="SessionStart", script=None):
        result = subprocess.run(
            ["/bin/sh", str(script or self.script)],
            input=json.dumps({"hook_event_name": event}),
            text=True,
            capture_output=True,
            env={**os.environ, "PATH": str(self.bin)},
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)["systemMessage"] if result.stdout else ""

    def test_all_required_plugins_enabled(self):
        self.set_listing([{"pluginId": "rules@settings", "installed": True, "enabled": True}])
        self.assertEqual(self.run_hook(), "")

    def test_missing_plugin(self):
        self.assertIn("rules@settings", self.run_hook())

    def test_disabled_plugin(self):
        self.set_listing([{"pluginId": "rules@settings", "installed": True, "enabled": False}])
        self.assertIn("rules@settings", self.run_hook())

    def test_multiple_marketplace_plugins(self):
        self.set_catalog("settings", ["rules", "editor", "docs"])
        self.set_listing([{"pluginId": "rules@settings", "installed": True, "enabled": True}])
        message = self.run_hook()
        self.assertIn("editor@settings", message)
        self.assertIn("docs@settings", message)
        self.assertNotIn("rules@settings", message)

    def test_python_absent(self):
        (self.bin / "python3").unlink()
        self.set_listing([{"pluginId": "rules@settings", "installed": True, "enabled": True}])
        self.assertIn("Python 3.9", self.run_hook())

    def test_python_unusable(self):
        self.stub("python3", "exit 1")
        self.assertIn("Python 3.9", self.run_hook())

    def test_jq_absent_still_returns_json_warning(self):
        (self.bin / "jq").unlink()
        self.assertIn("jq がないか実行できません", self.run_hook())

    def test_jq_unusable_still_returns_json_warning(self):
        (self.bin / "jq").unlink()
        self.stub("jq", "exit 1")
        self.assertIn("jq がないか実行できません", self.run_hook())

    def test_codex_absent(self):
        (self.bin / "codex").unlink()
        self.assertIn("codex がありません", self.run_hook())

    def test_codex_failure(self):
        self.stub("codex", "exit 1")
        self.assertIn("codex plugin list --json に失敗", self.run_hook())

    def test_invalid_plugin_listing(self):
        self.stub("codex", "printf 'not json'")
        self.assertIn("plugin 一覧が不正", self.run_hook())

    def test_invalid_marketplace(self):
        self.catalog.write_text("not json", encoding="utf-8")
        self.assertIn("marketplace.json が不正", self.run_hook())

    def test_non_session_event_does_not_check_plugins(self):
        self.stub("codex", "exit 1")
        self.assertEqual(self.run_hook("PreToolUse"), "")

    def test_stow_symlink_resolves_source_marketplace(self):
        readlink = shutil.which("readlink")
        if readlink is None:
            self.skipTest("readlink is required for a stow symlink")
        (self.bin / "readlink").symlink_to(readlink)
        linked = self.root / "home/.codex/scripts/check-required-plugins.sh"
        linked.parent.mkdir(parents=True)
        linked.symlink_to(self.script)
        self.assertIn("rules@settings", self.run_hook(script=linked))


if __name__ == "__main__":
    unittest.main()
