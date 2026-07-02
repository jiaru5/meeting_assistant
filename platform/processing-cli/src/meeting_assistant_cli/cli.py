from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .delete_session import run_delete_session
from .dependency_check import run_dependency_check
from .export_transcript import run_export_transcript
from .import_media import run_import_media
from .sanitization import redact_sensitive_text
from .settings import default_workspace
from .speaker_labeling import run_generate_speaker_labels
from .transcript_processing import run_generate_transcript


class ContractParseError(Exception):
    pass


class ContractArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ContractParseError(message)


EXIT_CODES = {
    "invalid_input": 2,
    "not_found": 3,
    "artifact_missing": 3,
    "path_conflict": 3,
    "permission_denied": 4,
    "dependency_missing": 4,
    "capture_failed": 5,
    "processing_failed": 5,
    "internal_error": 1,
}
KNOWN_COMMANDS = {
    "check_dependencies",
    "delete_session",
    "export_transcript",
    "generate_speaker_labels",
    "generate_transcript",
    "import_media",
}


def build_parser() -> argparse.ArgumentParser:
    parser = ContractArgumentParser(prog="meeting-assistant-cli")
    subparsers = parser.add_subparsers(dest="command", required=True, parser_class=ContractArgumentParser)

    check = subparsers.add_parser("check_dependencies")
    check.add_argument("--workspace-dir", default=None)
    check.add_argument("--format", choices=("json", "pretty"), default="json")

    import_media_parser = subparsers.add_parser("import_media")
    import_media_parser.add_argument("--path", required=True)
    import_media_parser.add_argument("--title", default=None)

    transcript = subparsers.add_parser("generate_transcript")
    transcript.add_argument("--session-id", required=True)
    transcript.add_argument("--source-artifact-id", default=None)
    transcript.add_argument("--language", default=None)
    transcript.add_argument("--runtime", default=None)

    speaker = subparsers.add_parser("generate_speaker_labels")
    speaker.add_argument("--session-id", required=True)
    speaker.add_argument("--transcript-id", required=True)
    speaker.add_argument("--allow-transcript-only-fallback", required=True, choices=("true", "false"))

    export = subparsers.add_parser("export_transcript")
    export.add_argument("--session-id", required=True)
    export.add_argument("--export-type", required=True, choices=("plain_text", "markdown", "json"))
    export.add_argument("--target-path", default=None)

    delete = subparsers.add_parser("delete_session")
    delete.add_argument("--session-id", required=True)
    delete.add_argument("--workspace-dir", default=None)
    delete.add_argument("--confirm", required=True, choices=("true", "false"))

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
    if response.get("target_path"):
        print(f"target_path: {response['target_path']}")
    for warning in response.get("warnings", []):
        print(f"warning: {warning}")


def _parse_failure_response(message: str, argv: Sequence[str] | None) -> dict:
    command = "unknown"
    if argv:
        first = str(argv[0])
        if first in KNOWN_COMMANDS:
            command = first
    return {
        "ok": False,
        "request_id": "local-parse-error",
        "command": command,
        "code": "invalid_input",
        "message": "Invalid command input.",
        "details": {"error": redact_sensitive_text(message, max_length=240, redact_paths=True)},
        "warnings": [],
    }


def main(argv: Sequence[str] | None = None) -> int:
    actual_argv = list(sys.argv[1:] if argv is None else argv)
    try:
        args = build_parser().parse_args(actual_argv)
    except ContractParseError as exc:
        response = _parse_failure_response(str(exc), actual_argv)
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    if args.command == "check_dependencies":
        workspace = Path(args.workspace_dir).expanduser() if args.workspace_dir else default_workspace()
        response = run_dependency_check(workspace)
        if args.format == "json":
            print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        else:
            _print_pretty(response)
        return _exit_code(response)
    if args.command == "import_media":
        response = run_import_media(Path(args.path), workspace=default_workspace(), title=args.title)
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    if args.command == "generate_transcript":
        response = run_generate_transcript(
            args.session_id,
            workspace=default_workspace(),
            source_artifact_id=args.source_artifact_id,
            language=args.language,
            runtime=args.runtime,
        )
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    if args.command == "generate_speaker_labels":
        response = run_generate_speaker_labels(
            args.session_id,
            args.transcript_id,
            workspace=default_workspace(),
            allow_transcript_only_fallback=args.allow_transcript_only_fallback == "true",
        )
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    if args.command == "export_transcript":
        response = run_export_transcript(
            args.session_id,
            args.export_type,
            workspace=default_workspace(),
            target_path=Path(args.target_path) if args.target_path else None,
        )
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    if args.command == "delete_session":
        workspace = Path(args.workspace_dir).expanduser() if args.workspace_dir else default_workspace()
        response = run_delete_session(
            args.session_id,
            workspace=workspace,
            confirm=args.confirm == "true",
        )
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return _exit_code(response)
    print(f"unsupported command: {args.command}", file=sys.stderr)
    return 2


def _exit_code(response: dict) -> int:
    if response["ok"]:
        return 0
    return EXIT_CODES.get(str(response.get("code", "internal_error")), 1)
