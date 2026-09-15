"""Check Claude settings separation and launch arguments in temporary homes."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "stow/claude"
ABBR = ROOT / "stow/fish/.config/fish/functions/__claude_abbr.fish"


class ClaudeSettingsTests(unittest.TestCase):
    def test_shared_settings_exclude_machine_keys(self):
        settings = json.loads((PACKAGE / ".claude/settings.json").read_text())
        self.assertNotIn("CLAUDE_HTML_COMMUNICATION_BASE_URL", settings["env"])
        self.assertNotIn("product-boilerplate", settings["extraKnownMarketplaces"])
        for plugin in ("ja-writing-ambiguity@cc-tools", "diffo@cc-tools"):
            self.assertIs(settings["enabledPlugins"][plugin], True)
        self.assertEqual(settings["env"]["CLAUDE_CODE_THRIFTY_SONIC"], "false")
        self.assertEqual(settings["modelSettings"]["claude-fable-5-1"]["effortLevel"], "high")
        for rule in (
            "Bash(/usr/bin/security find-generic-password*)",
            "Bash(security dump-keychain*)",
            "Bash(security find-generic-password*)",
        ):
            self.assertIn(rule, settings["permissions"]["deny"])

    @unittest.skipUnless(shutil.which("fish"), "fish is required")
    def test_abbr_with_without_machine_json_and_local_arguments(self):
        with tempfile.TemporaryDirectory(prefix="claude-abbr-") as temporary:
            home = Path(temporary) / "home with spaces"
            home.mkdir()
            env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}
            command = (
                "source $argv[1]; "
                "function __claude_abbr_local_args; printf '%s\\n' '--add-dir' '/tmp/local-probe'; end; "
                "__claude_abbr"
            )

            def expand():
                result = subprocess.run(
                    ["fish", "--no-config", "-c", command, str(ABBR)],
                    env=env, capture_output=True, text=True, check=True,
                )
                return shlex.split(result.stdout)

            base = ["claude", "--dangerously-skip-permissions"]
            local = ["--add-dir", "/tmp/local-probe"]
            self.assertEqual(expand(), base + local)
            machine = home / ".claude/settings.machine.json"
            machine.parent.mkdir()
            machine.write_text("{}\n")
            self.assertEqual(expand(), base + ["--settings", str(machine)] + local)

    @unittest.skipUnless(shutil.which("stow"), "stow is required")
    def test_stow_keeps_home_directory_real_and_ignores_machine_and_backup(self):
        with tempfile.TemporaryDirectory(prefix="claude-stow-") as temporary:
            root = Path(temporary)
            package = root / "stow/claude"
            shutil.copytree(PACKAGE, package)
            (package / ".claude/settings.json.bak").write_text("backup\n")
            (package / ".claude/settings.machine.json").write_text("{}\n")
            home = root / "home"
            home.mkdir()
            command = ["stow", "--no-folding", "--dir", str(root / "stow"), "--target", str(home), "claude"]
            for _ in range(2):
                subprocess.run(command, capture_output=True, text=True, check=True)
            self.assertFalse((home / ".claude").is_symlink())
            self.assertEqual((home / ".claude/settings.json").resolve(), (package / ".claude/settings.json").resolve())
            self.assertTrue((home / ".claude/settings.json").is_symlink())
            self.assertFalse((home / ".claude/settings.json.bak").exists())
            self.assertFalse((home / ".claude/settings.machine.json").exists())
