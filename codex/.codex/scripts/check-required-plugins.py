#!/usr/bin/env python3
"""Warn when a plugin required by the dotfiles marketplace is unavailable."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


MARKETPLACE = Path(__file__).resolve().parents[3] / ".agents/plugins/marketplace.json"


def required_plugin_ids(marketplace: Path) -> list[str]:
    catalog = json.loads(marketplace.read_text(encoding="utf-8"))
    name = catalog["name"]
    return sorted(f"{plugin['name']}@{name}" for plugin in catalog["plugins"])


def missing_plugin_ids(required: list[str], listing: dict) -> list[str]:
    enabled = {
        plugin["pluginId"]
        for plugin in listing["installed"]
        if plugin.get("installed") and plugin.get("enabled")
    }
    return [plugin_id for plugin_id in required if plugin_id not in enabled]


def warning(message: str) -> None:
    print(json.dumps({"systemMessage": message}, ensure_ascii=False))


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("hook_event_name") != "SessionStart":
            return 0
        required = required_plugin_ids(MARKETPLACE)
        result = subprocess.run(
            ["codex", "plugin", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=4,
            check=True,
        )
        missing = missing_plugin_ids(required, json.loads(result.stdout))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        warning(f"dotfiles の必須 Codex plugin を確認できません: {type(error).__name__}。セットアップ手順を確認してください。")
        return 0

    if missing:
        warning(
            "dotfiles の必須 Codex plugin が未導入または無効です: "
            + ", ".join(missing)
            + "。dotfiles のセットアップ手順に従ってインストールまたは有効化してください。"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
