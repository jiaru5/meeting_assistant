from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .dependency_check import default_workspace, run_dependency_check


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="meeting-assistant-cli")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check_dependencies")
    check.add_argument("--workspace-dir", default=None)
    check.add_argument("--format", choices=("json", "pretty"), default="json")

    return parser


def _print_pretty(response: dict) -> None:
    print(f"command: {response['command']}")
    print(f"ok: {str(response['ok']).lower()}")
    for item in response["checks"]:
        required = "required" if item["required"] else "optional"
        print(f"- {item['id']}: {item['status']} ({required}) - {item['message']}")
    for warning in response.get("warnings", []):
        print(f"warning: {warning}")


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "check_dependencies":
        workspace = Path(args.workspace_dir).expanduser() if args.workspace_dir else default_workspace()
        response = run_dependency_check(workspace)
        if args.format == "json":
            print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        else:
            _print_pretty(response)
        return 0 if response["ok"] else 1
    print(f"unsupported command: {args.command}", file=sys.stderr)
    return 2
