from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .dependency_check import run_dependency_check
from .import_media import run_import_media
from .settings import default_workspace


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="meeting-assistant-cli")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check_dependencies")
    check.add_argument("--workspace-dir", default=None)
    check.add_argument("--format", choices=("json", "pretty"), default="json")

    import_media_parser = subparsers.add_parser("import_media")
    import_media_parser.add_argument("--path", required=True)
    import_media_parser.add_argument("--title", default=None)
    import_media_parser.add_argument("--format", choices=("json", "pretty"), default="json")

    return parser


def _print_pretty(response: dict) -> None:
    print(f"command: {response['command']}")
    print(f"ok: {str(response['ok']).lower()}")
    if response.get("session_id"):
        print(f"session_id: {response['session_id']}")
    if response.get("code"):
        print(f"code: {response['code']}")
    if response.get("message"):
        print(f"message: {response['message']}")
    for item in response.get("checks", []):
        required = "required" if item["required"] else "optional"
        print(f"- {item['id']}: {item['status']} ({required}) - {item['message']}")
    for artifact in response.get("artifacts", []):
        print(
            f"- artifact {artifact['id']}: "
            f"{artifact['artifact_type']} {artifact['format']} {artifact['path']}"
        )
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
    if args.command == "import_media":
        response = run_import_media(Path(args.path), workspace=default_workspace(), title=args.title)
        if args.format == "json":
            print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        else:
            _print_pretty(response)
        return 0 if response["ok"] else 1
    print(f"unsupported command: {args.command}", file=sys.stderr)
    return 2
