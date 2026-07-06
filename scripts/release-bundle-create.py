#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


APP_BUNDLE_NAME = "MeetingAssistantNative.app"
DEFAULT_IDENTITY_PATTERN = "Developer ID Application:"
DEFAULT_DERIVED_DATA = ".harness/release-build/native-app/DerivedData"
DEFAULT_NOTARY_ARCHIVE = ".harness/release-build/native-app/MeetingAssistantNative-for-notary.zip"
DEFAULT_RELEASE_ARCHIVE = ".harness/release-inputs/bundle/MeetingAssistantNative-Release.zip"
DEFAULT_BUNDLE_REPORT = ".harness/release-inputs/bundle/release-bundle-report.json"


class ReleaseBundleError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def env_default(name: str) -> str | None:
    value = os.environ.get(name)
    if value is None or not value.strip():
        return None
    return value.strip()


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def require_non_empty(value: str | None, label: str) -> str:
    if value is None or not value.strip():
        raise ReleaseBundleError(f"{label} is required")
    return value.strip()


def current_commit(root: Path) -> str:
    output = run_command(["git", "-C", str(root), "rev-parse", "HEAD"], "git rev-parse HEAD")
    commit = output.strip()
    if not commit:
        raise ReleaseBundleError("unable to resolve current git commit")
    return commit


def source_repository(root: Path, configured: str | None) -> str:
    if configured is not None and configured.strip():
        return configured.strip()
    completed = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.url"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode == 0 and completed.stdout.strip():
        return completed.stdout.strip()
    raise ReleaseBundleError(
        "source repository is required; pass --source-repository or configure git remote.origin.url"
    )


def run_command(
    command: list[str],
    label: str,
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> str:
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise ReleaseBundleError(f"{label} failed: {exc.filename} is not available") from exc
    output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        lines = [line.strip() for line in output.strip().splitlines() if line.strip()]
        if len(lines) > 1 and lines[0].endswith("failed:"):
            detail = f"{lines[0]} {lines[1]}"
        else:
            detail = lines[0] if lines else f"exit {completed.returncode}"
        raise ReleaseBundleError(f"{label} failed: {detail}")
    return output


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def unlink_existing_file(path: Path) -> None:
    if path.exists():
        if not path.is_file():
            raise ReleaseBundleError(f"expected output path to be a file: {path}")
        path.unlink()


def require_release_identity(identity: str, identity_pattern: str) -> None:
    if identity_pattern not in identity:
        raise ReleaseBundleError(
            f"release signing identity must contain {identity_pattern!r}: {identity!r}"
        )


def check_release_credentials(root: Path, identity: str) -> None:
    run_command(
        [
            sys.executable,
            str(root / "scripts/release-credential-check.py"),
            "--root",
            str(root),
            "--identity-pattern",
            identity,
        ],
        "release credential prerequisite check",
    )


def build_release_app(
    root: Path,
    *,
    project: Path,
    scheme: str,
    destination: str,
    derived_data_path: Path,
    signing_identity: str,
    development_team: str | None,
) -> Path:
    command = [
        "xcodebuild",
        "build",
        "-configuration",
        "Release",
        "-project",
        str(project),
        "-scheme",
        scheme,
        "-destination",
        destination,
        "-derivedDataPath",
        str(derived_data_path),
        "CODE_SIGN_STYLE=Manual",
        f"CODE_SIGN_IDENTITY={signing_identity}",
        "OTHER_CODE_SIGN_FLAGS=--timestamp",
    ]
    if development_team is not None and development_team.strip():
        command.append(f"DEVELOPMENT_TEAM={development_team.strip()}")

    run_command(command, "xcodebuild Release app build", cwd=root)
    app_path = derived_data_path / "Build/Products/Release" / APP_BUNDLE_NAME
    if not app_path.is_dir():
        raise ReleaseBundleError(f"xcodebuild did not produce {APP_BUNDLE_NAME}: {app_path}")
    if not (app_path / "Contents/Info.plist").is_file():
        raise ReleaseBundleError(f"{APP_BUNDLE_NAME} is missing Contents/Info.plist: {app_path}")
    return app_path


def verify_signed_app(app_path: Path, signing_identity: str) -> None:
    run_command(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_path)],
        "codesign verify",
    )
    codesign_details = run_command(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(app_path)],
        "codesign details",
    )
    if "Signature=adhoc" in codesign_details:
        raise ReleaseBundleError("release app must not be ad-hoc signed")
    if signing_identity not in codesign_details:
        raise ReleaseBundleError("release app codesign details must include the selected signing identity")


def create_zip_archive(app_path: Path, archive_path: Path, label: str) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    unlink_existing_file(archive_path)
    run_command(
        ["/usr/bin/ditto", "-c", "-k", "--keepParent", str(app_path), str(archive_path)],
        label,
    )
    if not archive_path.is_file():
        raise ReleaseBundleError(f"{label} did not produce archive: {archive_path}")


def parse_notary_submission(output: str) -> str:
    text = output.strip()
    if not text:
        raise ReleaseBundleError("notarytool submit produced no output")

    if text.startswith("{"):
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ReleaseBundleError(f"notarytool JSON output is invalid: {exc}") from exc
        if not isinstance(payload, dict):
            raise ReleaseBundleError("notarytool JSON output must be an object")
        status = str(payload.get("status", "")).strip()
        submission_id = str(payload.get("id", "")).strip()
    else:
        status_match = re.search(r"(?im)^\s*status:\s*([A-Za-z]+)\s*$", text)
        id_match = re.search(r"(?im)^\s*id:\s*([A-Za-z0-9-]+)\s*$", text)
        status = status_match.group(1).strip() if status_match else ""
        submission_id = id_match.group(1).strip() if id_match else ""

    if status != "Accepted":
        raise ReleaseBundleError(f"notarytool submission must be Accepted, got {status or 'unknown'}")
    if not submission_id:
        raise ReleaseBundleError("notarytool submission id is required for release bundle evidence")
    return submission_id


def notarize_and_staple(app_path: Path, notary_archive: Path, notary_profile: str) -> str:
    create_zip_archive(app_path, notary_archive, "notary upload archive")
    notary_output = run_command(
        [
            "/usr/bin/xcrun",
            "notarytool",
            "submit",
            str(notary_archive),
            "--keychain-profile",
            notary_profile,
            "--wait",
        ],
        "notarytool submit",
    )
    submission_id = parse_notary_submission(notary_output)
    run_command(["/usr/bin/xcrun", "stapler", "staple", str(app_path)], "stapler staple")
    run_command(["/usr/bin/xcrun", "stapler", "validate", str(app_path)], "stapler validate")
    run_command(["/usr/sbin/spctl", "-a", "-t", "exec", "-vv", str(app_path)], "spctl assess")
    return submission_id


def build_bundle_report(
    *,
    subject_commit: str,
    builder: str,
    source_repository_value: str,
    release_archive: Path,
    signing_identity: str,
    notarization_ticket: str,
) -> dict[str, Any]:
    return {
        "report_schema": 1,
        "release_gate": "release-bundle",
        "subject_commit": subject_commit,
        "builder": builder,
        "source_repository": source_repository_value,
        "bundle": {
            "name": release_archive.name,
            "path": str(release_archive),
            "digest": sha256_file(release_archive),
            "artifact_type": "macos-app-archive",
            "archive_format": "zip",
            "app_bundle": APP_BUNDLE_NAME,
            "build_configuration": "Release",
            "code_signed": True,
            "signing_identity": signing_identity,
            "notarized": True,
            "notarization_ticket": notarization_ticket,
            "stapled": True,
            "packages_runtime_or_model": False,
            "auto_downloads": False,
            "contains_meeting_data": False,
        },
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def create_release_bundle(args: argparse.Namespace) -> dict[str, Any]:
    root = resolve_path(repo_root_from_script(), args.root)
    signing_identity = require_non_empty(args.signing_identity, "release signing identity")
    identity_pattern = require_non_empty(args.identity_pattern, "release signing identity pattern")
    notary_profile = require_non_empty(args.notary_profile, "notarytool keychain profile")
    builder = require_non_empty(args.builder, "builder")
    source_repo = source_repository(root, args.source_repository)

    require_release_identity(signing_identity, identity_pattern)
    check_release_credentials(root, signing_identity)

    project = resolve_path(root, args.project)
    derived_data_path = resolve_path(root, args.derived_data_path)
    notary_archive = resolve_path(root, args.notary_archive)
    release_archive = resolve_path(root, args.output)
    bundle_report_path = resolve_path(root, args.report)

    app_path = build_release_app(
        root,
        project=project,
        scheme=args.scheme,
        destination=args.destination,
        derived_data_path=derived_data_path,
        signing_identity=signing_identity,
        development_team=args.development_team,
    )
    verify_signed_app(app_path, signing_identity)
    submission_id = notarize_and_staple(app_path, notary_archive, notary_profile)
    create_zip_archive(app_path, release_archive, "release archive")

    report = build_bundle_report(
        subject_commit=current_commit(root),
        builder=builder,
        source_repository_value=source_repo,
        release_archive=release_archive,
        signing_identity=signing_identity,
        notarization_ticket=submission_id,
    )
    write_json(bundle_report_path, report)

    if not args.skip_release_bundle_check:
        env = os.environ.copy()
        env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_report_path)
        run_command([str(root / "scripts/release-bundle-check.sh")], "release bundle check", cwd=root, env=env)

    print(f"release archive: {release_archive}")
    print(f"release bundle report: {bundle_report_path}")
    print(
        "VS-MA-23 release bundle produced [non-bypass]: "
        "generate DSSE/SLSA and Sigstore inputs, then run release-inputs-report.py and release-preflight.sh"
    )
    return report


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build, Developer ID sign, notarize, staple, zip, and report the "
            "MeetingAssistantNative Release app bundle."
        )
    )
    parser.add_argument("--root", default=str(repo_root_from_script()))
    parser.add_argument(
        "--project",
        default="platform/native-app/MeetingAssistantNative.xcodeproj",
        help="Path to the native Xcode project.",
    )
    parser.add_argument("--scheme", default="MeetingAssistantNative")
    parser.add_argument(
        "--destination",
        default=env_default("MA_NATIVE_RELEASE_XCODE_DESTINATION") or "platform=macOS",
    )
    parser.add_argument("--derived-data-path", default=DEFAULT_DERIVED_DATA)
    parser.add_argument("--notary-archive", default=DEFAULT_NOTARY_ARCHIVE)
    parser.add_argument("--output", default=DEFAULT_RELEASE_ARCHIVE)
    parser.add_argument("--report", default=DEFAULT_BUNDLE_REPORT)
    parser.add_argument(
        "--signing-identity",
        default=env_default("MEETING_ASSISTANT_RELEASE_SIGNING_IDENTITY"),
        help="Developer ID Application signing identity. Also accepted from MEETING_ASSISTANT_RELEASE_SIGNING_IDENTITY.",
    )
    parser.add_argument(
        "--identity-pattern",
        default=env_default("MEETING_ASSISTANT_RELEASE_IDENTITY_PATTERN") or DEFAULT_IDENTITY_PATTERN,
        help="Required substring for the signing identity.",
    )
    parser.add_argument(
        "--development-team",
        default=env_default("MEETING_ASSISTANT_RELEASE_DEVELOPMENT_TEAM"),
        help="Optional Apple developer team id passed to xcodebuild.",
    )
    parser.add_argument(
        "--notary-profile",
        default=env_default("MEETING_ASSISTANT_NOTARYTOOL_PROFILE"),
        help="notarytool keychain profile. Also accepted from MEETING_ASSISTANT_NOTARYTOOL_PROFILE.",
    )
    parser.add_argument(
        "--builder",
        default=env_default("MEETING_ASSISTANT_RELEASE_BUILDER") or "local-release-rehearsal",
    )
    parser.add_argument(
        "--source-repository",
        default=env_default("MEETING_ASSISTANT_RELEASE_SOURCE_REPOSITORY"),
    )
    parser.add_argument(
        "--skip-release-bundle-check",
        action="store_true",
        help="Write the bundle report without running release-bundle-check.sh. Intended only for local debugging.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    create_release_bundle(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except ReleaseBundleError as exc:
        print(f"release bundle creation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
