"""Check the one-time shared-skills setup without touching the user home."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/setup-shared-skills.sh"


class SharedSkillsSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary_home = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_home.cleanup)
        self.home = Path(self.temporary_home.name)
        self.source = self.home / ".claude/skills"
        self.target = self.home / ".agents/skills"

    def run_setup(self):
        environment = os.environ.copy()
        environment["DOTFILES_SETUP_HOME"] = str(self.home)
        return subprocess.run(
            ["/bin/sh", str(SCRIPT)],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )

    def test_creates_relative_link_and_is_idempotent(self):
        self.source.mkdir(parents=True)
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(os.readlink(self.target), "../.claude/skills")
        self.assertEqual(self.target.resolve(), self.source.resolve())
        self.assertEqual(self.run_setup().returncode, 0)

    def test_missing_source_does_not_create_target(self):
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.target.exists())
        self.assertIn("skills source does not exist", result.stderr)

    def test_existing_directory_is_preserved(self):
        self.source.mkdir(parents=True)
        self.target.mkdir(parents=True)
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.target.is_dir())

    def test_other_symlink_is_preserved(self):
        self.source.mkdir(parents=True)
        self.target.parent.mkdir()
        self.target.symlink_to("../other-skills")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(os.readlink(self.target), "../other-skills")
