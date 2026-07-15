#!/usr/bin/env -S /usr/bin/python3 -I -S
"""Verify and export the MVP.1 task XCUITest result bundle offline."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path
from typing import Any


TEST_CLASS = "DesignedNativeShellAppBundleTests"
EXPECTED_TEST_COUNT = 17
REQUIRED_SCREENSHOTS = (
    "00-meetings-recent",
    "01-meetings-empty",
    "02-new-recording-ready",
    "03-recording-live",
    "04-recording-saved",
    "05-processing",
    "06-transcript-ready",
    "07-diagnostics",
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TEST_METHOD_PATTERN = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]+)\s*\(", re.MULTILINE)
CDHASH_PATTERN = re.compile(r"^CDHash=([0-9a-fA-F]+)$", re.MULTILINE)
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
XCODE_ATTACHMENT_SCREENSHOT_SUFFIX = re.compile(
    r"_[0-9]+_[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\.png$"
)
FINGERPRINT_PATHS = (
    "platform/native-app/App",
    "platform/native-app/Sources",
    "platform/native-app/UITests",
    "platform/native-app/MeetingAssistantNative.xcodeproj/project.pbxproj",
    "platform/native-app/MeetingAssistantNative.xcodeproj/xcshareddata",
)
EXECUTED_VERIFIER_SHA256_ENV = "MA_MVP1_EXECUTED_VERIFIER_SHA256"
TRUSTED_XCRUN = Path("/usr/bin/xcrun")
TRUSTED_ENV = Path("/usr/bin/env")
TRUSTED_PYTHON_LAUNCHER = Path("/usr/bin/python3")
TRUSTED_CODESIGN = Path("/usr/bin/codesign")
TRUSTED_GIT = Path("/usr/bin/git")
TRUSTED_IMAGE_DECODER = Path("/usr/bin/sips")


class VerificationError(RuntimeError):
    pass


def executed_verifier_sha256() -> str:
    value = os.environ.get(EXECUTED_VERIFIER_SHA256_ENV, "")
    if not SHA256_PATTERN.fullmatch(value):
        raise VerificationError(
            f"{EXECUTED_VERIFIER_SHA256_ENV} must be set by the verified snapshot loader"
        )
    return value


def _verify_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xcresult", required=True)
    parser.add_argument("--derived-data-root", required=True)
    parser.add_argument("--xctestrun", required=True)
    parser.add_argument("--input-fingerprint-file", required=True)
    parser.add_argument("--expected-input-fingerprint", required=True)
    parser.add_argument("--expected-subject-commit", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--test-source", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--runner", required=True)
    parser.add_argument("--artifact-binding-file", required=True)
    parser.add_argument("--expected-artifact-binding-sha256", required=True)
    parser.add_argument("--verifier-source", required=True)
    parser.add_argument("--expected-verifier-sha256", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--upstream-test-status", type=int, default=0)
    parser.add_argument("--xcresulttool")
    parser.add_argument("--codesign-tool", default="/usr/bin/codesign")
    parser.add_argument("--git-tool", default="/usr/bin/git")
    parser.add_argument("--xcodebuild-tool")
    parser.add_argument("--image-decode-tool", default="/usr/bin/sips")
    parser.add_argument("--fixture-mode", action="store_true", help=argparse.SUPPRESS)
    return parser


def _capture_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Capture the exact prepared task artifacts immediately before XCUITest."
    )
    parser.add_argument("--derived-data-root", required=True)
    parser.add_argument("--xctestrun", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--runner", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--xcresulttool")
    parser.add_argument("--codesign-tool", default="/usr/bin/codesign")
    parser.add_argument("--git-tool", default="/usr/bin/git")
    parser.add_argument("--xcodebuild-tool")
    parser.add_argument("--image-decode-tool", default="/usr/bin/sips")
    parser.add_argument("--fixture-mode", action="store_true", help=argparse.SUPPRESS)
    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    values = list(sys.argv[1:] if argv is None else argv)
    if values[:1] == ["capture"]:
        args = _capture_parser().parse_args(values[1:])
        args.mode = "capture"
        return args
    if values[:1] == ["verify"]:
        values = values[1:]
    args = _verify_parser().parse_args(values)
    args.mode = "verify"
    return args


def path_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def resolve_output(path_text: str) -> Path:
    absolute = Path(os.path.abspath(os.path.expanduser(path_text)))
    return absolute.parent.resolve() / absolute.name


def resolve_input(path_text: str, *, name: str, kind: str = "any") -> Path:
    path = Path(path_text).expanduser().resolve()
    valid = path.exists()
    if kind == "file":
        valid = path.is_file()
    elif kind == "dir":
        valid = path.is_dir()
    if not valid:
        raise VerificationError(f"{name} does not exist as a {kind}: {path}")
    return path


def run_json(command: list[str], *, description: str) -> dict[str, Any]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise VerificationError(f"{description} failed with exit {completed.returncode}: {detail}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise VerificationError(f"{description} returned invalid JSON: {error}") from error
    if not isinstance(payload, dict):
        raise VerificationError(f"{description} returned a non-object JSON value")
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def absolute_tool_path(value: str | Path) -> Path:
    return Path(os.path.abspath(os.path.expanduser(os.fspath(value))))


def xcrun_find(tool_name: str) -> Path:
    completed = subprocess.run(
        [str(TRUSTED_XCRUN), "--find", tool_name],
        check=False,
        capture_output=True,
        text=True,
    )
    candidate = completed.stdout.strip()
    if completed.returncode != 0 or not candidate:
        detail = (completed.stderr or completed.stdout).strip()
        raise VerificationError(
            f"trusted xcrun could not resolve {tool_name}: {detail or 'no path returned'}"
        )
    path = absolute_tool_path(candidate)
    if not path.is_absolute():
        raise VerificationError(f"trusted xcrun returned a non-absolute {tool_name} path")
    return path


def executable_identity(
    path: Path,
    *,
    label: str,
    require_apple_anchor: bool,
) -> dict[str, Any]:
    try:
        resolved_path = path.resolve(strict=True)
    except OSError as error:
        raise VerificationError(f"{label} could not be resolved safely: {path}: {error}") from error
    if (
        not path.is_absolute()
        or not path.is_file()
        or not os.access(path, os.X_OK)
        or not resolved_path.is_file()
        or not os.access(resolved_path, os.X_OK)
    ):
        raise VerificationError(
            f"{label} must resolve from an absolute executable path to a regular executable: {path}"
        )
    apple_anchor_verified = False
    if require_apple_anchor:
        completed = subprocess.run(
            [
                str(TRUSTED_CODESIGN),
                "--verify",
                "--strict",
                "--test-requirement",
                "=anchor apple",
                str(resolved_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()
            raise VerificationError(
                f"{label} is not verified against the Apple code-signing anchor: {detail}"
            )
        apple_anchor_verified = True
    return {
        "path": str(path),
        "resolved_path": str(resolved_path),
        "sha256": sha256_file(resolved_path),
        "apple_anchor_verified": apple_anchor_verified,
    }


def validated_toolchain(args: argparse.Namespace) -> dict[str, Any]:
    expected_python = xcrun_find("python3")
    expected_xcodebuild = xcrun_find("xcodebuild")
    expected_xcresulttool = xcrun_find("xcresulttool")
    expected = {
        "env": TRUSTED_ENV,
        "xcrun": TRUSTED_XCRUN,
        "python_launcher": TRUSTED_PYTHON_LAUNCHER,
        "python": expected_python,
        "xcodebuild": expected_xcodebuild,
        "xcresulttool": expected_xcresulttool,
        "codesign": TRUSTED_CODESIGN,
        "git": TRUSTED_GIT,
        "image_decoder": TRUSTED_IMAGE_DECODER,
    }
    configured = {
        "env": TRUSTED_ENV,
        "xcrun": TRUSTED_XCRUN,
        "python_launcher": TRUSTED_PYTHON_LAUNCHER,
        "python": absolute_tool_path(sys.executable),
        "xcodebuild": absolute_tool_path(args.xcodebuild_tool or expected_xcodebuild),
        "xcresulttool": absolute_tool_path(args.xcresulttool or expected_xcresulttool),
        "codesign": absolute_tool_path(args.codesign_tool),
        "git": absolute_tool_path(args.git_tool),
        "image_decoder": absolute_tool_path(args.image_decode_tool),
    }
    mode = "fixture" if args.fixture_mode else "trusted"
    if mode == "trusted":
        for label, expected_path in expected.items():
            if configured[label] != expected_path:
                raise VerificationError(
                    f"trusted task evidence requires {label} at {expected_path}; "
                    f"observed {configured[label]}"
                )
    identities = {
        label: executable_identity(
            path,
            label=label,
            require_apple_anchor=mode == "trusted",
        )
        for label, path in configured.items()
    }
    args.xcodebuild_tool = identities["xcodebuild"]["path"]
    args.xcresulttool = identities["xcresulttool"]["path"]
    args.codesign_tool = identities["codesign"]["path"]
    args.git_tool = identities["git"]["path"]
    args.image_decode_tool = identities["image_decoder"]["path"]
    return {"mode": mode, "tools": identities}


def clean_git_environment() -> dict[str, str]:
    return {
        "GIT_CONFIG_NOSYSTEM": "1",
        "HOME": "/var/empty",
        "LANG": "C",
        "PATH": "/usr/bin:/bin",
    }


def directory_manifest(path: Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    file_count = 0
    total_bytes = 0
    for item in sorted(path.rglob("*"), key=lambda candidate: candidate.as_posix()):
        if item.is_symlink():
            raise VerificationError(f"retained artifact directory contains a symlink: {item}")
        if item.is_dir():
            continue
        if not item.is_file():
            raise VerificationError(f"retained artifact directory contains a non-file entry: {item}")
        relative = item.relative_to(path).as_posix()
        size = item.stat().st_size
        file_sha256 = sha256_file(item)
        digest.update(f"{relative}\0{size}\0{file_sha256}\n".encode("utf-8"))
        file_count += 1
        total_bytes += size
    if file_count == 0:
        raise VerificationError(f"retained artifact directory is empty: {path}")
    return {
        "manifest_sha256": digest.hexdigest(),
        "file_count": file_count,
        "total_bytes": total_bytes,
    }


def secure_evidence_tree(path: Path) -> None:
    if path.is_symlink():
        raise VerificationError(f"evidence path must not be a symlink: {path}")
    for item in [path, *path.rglob("*")]:
        if item.is_symlink():
            raise VerificationError(f"evidence tree must not contain a symlink: {item}")
        if item.is_dir():
            os.chmod(item, 0o700)
        elif item.is_file():
            os.chmod(item, 0o600)


def read_input_fingerprint(path: Path) -> str:
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise VerificationError(f"could not read prepared input fingerprint: {error}") from error
    if not SHA256_PATTERN.fullmatch(value):
        raise VerificationError("prepared input fingerprint must be one lowercase SHA-256 value")
    return value


def compute_current_input_fingerprint(
    *,
    repo_root: Path,
    destination: str,
    git_tool: str,
    xcodebuild_tool: str,
) -> str:
    try:
        version = subprocess.run(
            [xcodebuild_tool, "-version"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise VerificationError(f"could not execute xcodebuild for current fingerprint: {error}") from error
    if version.returncode != 0:
        detail = (version.stderr or version.stdout).strip()
        raise VerificationError(f"xcodebuild -version failed while recomputing fingerprint: {detail}")
    try:
        tracked = subprocess.run(
            [
                git_tool,
                "-C",
                str(repo_root),
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
                "--",
                *FINGERPRINT_PATHS,
            ],
            check=False,
            capture_output=True,
            env=clean_git_environment(),
        )
    except OSError as error:
        raise VerificationError(f"could not enumerate current task inputs: {error}") from error
    if tracked.returncode != 0:
        detail = (tracked.stderr or tracked.stdout).decode("utf-8", errors="replace").strip()
        raise VerificationError(f"could not enumerate current task inputs: {detail}")

    fingerprint_input = bytearray(f"destination={destination}\n".encode("utf-8"))
    for line in version.stdout.splitlines():
        fingerprint_input.extend(f"xcodebuild={line}\n".encode("utf-8"))
    for raw_relative in tracked.stdout.split(b"\0"):
        if not raw_relative:
            continue
        relative = os.fsdecode(raw_relative)
        absolute = repo_root / relative
        if not absolute.is_file():
            raise VerificationError(f"current task fingerprint input is not a file: {absolute}")
        fingerprint_input.extend(f"path={relative}\n".encode("utf-8"))
        fingerprint_input.extend(
            f"{sha256_file(absolute)}  {absolute}\n".encode("utf-8")
        )
    return hashlib.sha256(fingerprint_input).hexdigest()


def xcresult_command(tool: str, *arguments: str) -> list[str]:
    command = [tool]
    if Path(tool).name == "xcrun":
        command.append("xcresulttool")
    command.extend(arguments)
    return command


def source_test_methods(source_path: Path) -> list[str]:
    methods = TEST_METHOD_PATTERN.findall(source_path.read_text(encoding="utf-8"))
    duplicates = sorted({name for name in methods if methods.count(name) > 1})
    if duplicates:
        raise VerificationError(f"duplicate task test methods in source: {', '.join(duplicates)}")
    return sorted(methods)


def flatten_test_cases(payload: dict[str, Any]) -> list[dict[str, str]]:
    cases: list[dict[str, str]] = []

    def visit(node: Any, ancestry: tuple[str, ...]) -> None:
        if not isinstance(node, dict):
            return
        name = str(node.get("name", ""))
        identifier = str(node.get("nodeIdentifier", ""))
        identifier_url = str(node.get("nodeIdentifierURL", ""))
        context = " ".join((*ancestry, name, identifier, identifier_url))
        if node.get("nodeType") == "Test Case" and TEST_CLASS in context:
            method_match = re.search(r"(test[A-Za-z0-9_]+)(?:\(\))?", name)
            if method_match is None:
                method_match = re.search(r"(test[A-Za-z0-9_]+)(?:\(\))?", identifier)
            if method_match is None:
                raise VerificationError(f"could not parse task test method from xcresult node: {name!r}")
            cases.append(
                {
                    "method": method_match.group(1),
                    "result": str(node.get("result", "unknown")),
                    "identifier": identifier,
                }
            )
        next_ancestry = (*ancestry, name, identifier)
        for child in node.get("children", []):
            visit(child, next_ancestry)

    for root in payload.get("testNodes", []):
        visit(root, ())
    return cases


def read_bundle_identity(bundle_path: Path, codesign_tool: str, label: str) -> dict[str, str]:
    bundle_path = bundle_path.expanduser().resolve()
    plist_path = bundle_path / "Contents" / "Info.plist"
    if not plist_path.is_file():
        raise VerificationError(f"{label} Info.plist is missing: {plist_path}")
    try:
        with plist_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise VerificationError(f"could not read {label} Info.plist: {error}") from error
    bundle_id = str(info.get("CFBundleIdentifier", "")).strip()
    executable_name = str(info.get("CFBundleExecutable", "")).strip()
    executable_path = bundle_path / "Contents" / "MacOS" / executable_name
    if not bundle_id or not executable_name or not executable_path.is_file():
        raise VerificationError(
            f"{label} identity is incomplete (bundle id and executable are required): {bundle_path}"
        )
    verified = subprocess.run(
        [codesign_tool, "--verify", "--deep", "--strict", str(bundle_path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if verified.returncode != 0:
        detail = (verified.stderr or verified.stdout).strip()
        raise VerificationError(f"{label} strict code-signature verification failed: {detail}")
    completed = subprocess.run(
        [codesign_tool, "-dvvv", str(bundle_path)],
        check=False,
        capture_output=True,
        text=True,
    )
    codesign_output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    cdhash_match = CDHASH_PATTERN.search(codesign_output)
    cdhash = cdhash_match.group(1).lower() if cdhash_match else ""
    if completed.returncode != 0 or not cdhash:
        raise VerificationError(
            f"{label} identity is incomplete (path, bundle id and cdhash are required): "
            f"path={bundle_path}, bundle_id={bundle_id or 'missing'}, cdhash={cdhash or 'missing'}"
        )
    return {
        "path": str(bundle_path),
        "bundle_id": bundle_id,
        "cdhash": cdhash,
        "executable_path": str(executable_path),
        "executable_sha256": sha256_file(executable_path),
    }


def expand_xctestrun_path(value: Any, *, test_root: Path, test_host: Path | None = None) -> Path:
    if not isinstance(value, str) or not value:
        raise VerificationError("xctestrun product path is missing")
    expanded = value.replace("__TESTROOT__", str(test_root))
    if test_host is not None:
        expanded = expanded.replace("__TESTHOST__", str(test_host))
    if re.search(r"__[A-Z0-9_]+__", expanded):
        raise VerificationError(f"xctestrun product path contains an unresolved placeholder: {value}")
    return Path(expanded).expanduser().resolve()


def read_xctestrun_binding(
    *,
    xctestrun_path: Path,
    app_path: Path,
    runner_path: Path,
    app_identity: dict[str, str],
    runner_identity: dict[str, str],
) -> dict[str, Any]:
    xctestrun_path = xctestrun_path.expanduser().resolve()
    try:
        with xctestrun_path.open("rb") as handle:
            payload = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise VerificationError(f"could not read xctestrun plist: {error}") from error
    if not isinstance(payload, dict):
        raise VerificationError("xctestrun plist must be a dictionary")
    configuration = payload.get("MeetingAssistantNativeAppUITests")
    if not isinstance(configuration, dict):
        raise VerificationError("xctestrun is missing MeetingAssistantNativeAppUITests configuration")
    if configuration.get("BlueprintName") != "MeetingAssistantNativeAppUITests":
        raise VerificationError("xctestrun UI test blueprint does not match the task suite")
    if configuration.get("IsUITestBundle") is not True:
        raise VerificationError("xctestrun task configuration is not a UI test bundle")

    test_root = xctestrun_path.parent.resolve()
    bound_runner = expand_xctestrun_path(
        configuration.get("TestHostPath"), test_root=test_root
    )
    bound_app = expand_xctestrun_path(
        configuration.get("UITargetAppPath"), test_root=test_root
    )
    test_bundle = expand_xctestrun_path(
        configuration.get("TestBundlePath"), test_root=test_root, test_host=bound_runner
    )
    if bound_app != app_path:
        raise VerificationError(
            f"xctestrun target app path {bound_app} does not match verified app path {app_path}"
        )
    if bound_runner != runner_path:
        raise VerificationError(
            f"xctestrun test host path {bound_runner} does not match verified runner path {runner_path}"
        )
    if not test_bundle.exists():
        raise VerificationError(f"xctestrun UI test bundle is missing: {test_bundle}")
    if configuration.get("TestHostBundleIdentifier") != runner_identity["bundle_id"]:
        raise VerificationError("xctestrun test host bundle identifier does not match the runner")
    crash_emphasis_ids = configuration.get("BundleIdentifiersForCrashReportEmphasis", [])
    if not isinstance(crash_emphasis_ids, list) or app_identity["bundle_id"] not in crash_emphasis_ids:
        raise VerificationError("xctestrun does not bind the verified target app bundle identifier")
    return {
        "path": str(xctestrun_path),
        "sha256": sha256_file(xctestrun_path),
        "configuration": "MeetingAssistantNativeAppUITests",
        "target_app_path": str(bound_app),
        "test_host_path": str(bound_runner),
        "test_bundle_path": str(test_bundle),
    }


def capture_artifact_binding(
    *,
    xctestrun_path: Path,
    app_path: Path,
    runner_path: Path,
    codesign_tool: str,
    captured_by_verifier_sha256: str,
    toolchain: dict[str, Any] | None = None,
) -> dict[str, Any]:
    app_identity = read_bundle_identity(app_path, codesign_tool, "target app")
    runner_identity = read_bundle_identity(runner_path, codesign_tool, "UI test runner")
    app_path = Path(app_identity["path"])
    runner_path = Path(runner_identity["path"])
    xctestrun = read_xctestrun_binding(
        xctestrun_path=xctestrun_path,
        app_path=app_path,
        runner_path=runner_path,
        app_identity=app_identity,
        runner_identity=runner_identity,
    )
    test_bundle_identity = read_bundle_identity(
        Path(xctestrun["test_bundle_path"]),
        codesign_tool,
        "UI test bundle",
    )
    binding = {
        "schema_version": 1,
        "binding_type": "mvp1-task-artifacts-before-test",
        "captured_by_verifier_sha256": captured_by_verifier_sha256,
        "xctestrun": xctestrun,
        "app_identity": app_identity,
        "runner_identity": runner_identity,
        "test_bundle_identity": test_bundle_identity,
    }
    if toolchain is not None:
        binding["toolchain"] = toolchain
    return binding


def read_artifact_binding(path: Path) -> tuple[dict[str, Any], str]:
    try:
        payload = path.read_bytes()
        value = json.loads(payload.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"prepared artifact binding is unreadable: {error}") from error
    if not isinstance(value, dict):
        raise VerificationError("prepared artifact binding must be a JSON object")
    if value.get("schema_version") != 1 or value.get("binding_type") != (
        "mvp1-task-artifacts-before-test"
    ):
        raise VerificationError("prepared artifact binding has the wrong schema or type")
    verifier_sha256 = value.get("captured_by_verifier_sha256")
    if not isinstance(verifier_sha256, str) or not SHA256_PATTERN.fullmatch(verifier_sha256):
        raise VerificationError("prepared artifact binding has no valid capture verifier SHA-256")
    return value, hashlib.sha256(payload).hexdigest()


def validate_artifact_binding(
    expected: dict[str, Any],
    observed: dict[str, Any],
    findings: list[str],
) -> None:
    for key in (
        "xctestrun",
        "app_identity",
        "runner_identity",
        "test_bundle_identity",
        "toolchain",
    ):
        if expected.get(key) != observed.get(key):
            findings.append(f"prepared {key} changed during task evidence collection")


def current_commit(repo_root: Path, git_tool: str) -> str:
    try:
        completed = subprocess.run(
            [git_tool, "-C", str(repo_root), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            env=clean_git_environment(),
        )
    except OSError as error:
        raise VerificationError(f"could not execute Git to bind task evidence: {error}") from error
    commit = completed.stdout.strip()
    if completed.returncode != 0 or not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
        raise VerificationError("could not bind task xcresult evidence to the current Git commit")
    return commit.lower()


def require_clean_task_subject(repo_root: Path, git_tool: str) -> None:
    try:
        completed = subprocess.run(
            [
                git_tool,
                "-C",
                str(repo_root),
                "status",
                "--porcelain=v1",
                "--untracked-files=all",
                "--",
                "platform/native-app/App",
                "platform/native-app/Sources",
                "platform/native-app/UITests",
                "platform/native-app/MeetingAssistantNative.xcodeproj/project.pbxproj",
                "platform/native-app/MeetingAssistantNative.xcodeproj/xcshareddata",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=clean_git_environment(),
        )
    except OSError as error:
        raise VerificationError(f"could not inspect current task subject worktree: {error}") from error
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise VerificationError(f"could not inspect current task subject worktree: {detail}")
    if completed.stdout.strip():
        raise VerificationError(
            "task app/UI-test subject paths have uncommitted or untracked changes; "
            "commit them before collecting commit-bound evidence"
        )


def png_dimensions(path: Path) -> tuple[int, int]:
    try:
        payload = path.read_bytes()
    except OSError as error:
        raise VerificationError(f"could not read exported PNG: {error}") from error
    if not payload.startswith(PNG_SIGNATURE):
        raise VerificationError("exported attachment does not have a PNG signature")
    offset = len(PNG_SIGNATURE)
    width = 0
    height = 0
    saw_ihdr = False
    saw_idat = False
    saw_iend = False
    chunk_index = 0
    while offset < len(payload):
        if offset + 12 > len(payload):
            raise VerificationError("exported PNG has a truncated chunk header")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4
        if crc_end > len(payload):
            raise VerificationError("exported PNG has a truncated chunk payload")
        expected_crc = struct.unpack(">I", payload[data_end:crc_end])[0]
        observed_crc = zlib.crc32(chunk_type)
        observed_crc = zlib.crc32(payload[data_start:data_end], observed_crc) & 0xFFFFFFFF
        if observed_crc != expected_crc:
            raise VerificationError("exported PNG has an invalid chunk CRC")
        if chunk_index == 0 and chunk_type != b"IHDR":
            raise VerificationError("exported PNG does not start with IHDR")
        if chunk_type == b"IHDR":
            if saw_ihdr or length != 13:
                raise VerificationError("exported PNG has an invalid IHDR")
            width, height = struct.unpack(">II", payload[data_start : data_start + 8])
            if width <= 0 or height <= 0:
                raise VerificationError("exported PNG dimensions must be non-zero")
            saw_ihdr = True
        elif chunk_type == b"IDAT":
            saw_idat = True
        elif chunk_type == b"IEND":
            if length != 0:
                raise VerificationError("exported PNG has an invalid IEND")
            saw_iend = True
            if crc_end != len(payload):
                raise VerificationError("exported PNG contains data after IEND")
            break
        offset = crc_end
        chunk_index += 1
    if not saw_ihdr or not saw_idat or not saw_iend:
        raise VerificationError("exported PNG is missing IHDR, IDAT, or IEND")
    return width, height


def verify_png_decode(path: Path, decode_tool: str) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.stem}.decode-",
        suffix=".png",
        dir=path.parent,
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    temporary.unlink()
    try:
        completed = subprocess.run(
            [decode_tool, "-s", "format", "png", str(path), "--out", str(temporary)],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0 or not temporary.is_file() or temporary.stat().st_size == 0:
            detail = (completed.stderr or completed.stdout).strip()
            raise VerificationError(
                f"exported PNG failed full image decode with exit {completed.returncode}: {detail}"
            )
    except OSError as error:
        raise VerificationError(f"could not execute PNG decode tool: {error}") from error
    finally:
        temporary.unlink(missing_ok=True)


def validate_summary(summary: dict[str, Any], findings: list[str]) -> dict[str, Any]:
    expected = {
        "result": "Passed",
        "totalTestCount": EXPECTED_TEST_COUNT,
        "passedTests": EXPECTED_TEST_COUNT,
        "failedTests": 0,
        "skippedTests": 0,
        "expectedFailures": 0,
    }
    observed = {key: summary.get(key) for key in expected}
    for key, value in expected.items():
        if observed[key] != value:
            findings.append(f"summary {key} must be {value!r}, observed {observed[key]!r}")
    return observed


def validate_tests(
    source_methods: list[str], test_cases: list[dict[str, str]], findings: list[str]
) -> list[dict[str, str]]:
    if len(source_methods) != EXPECTED_TEST_COUNT:
        findings.append(
            f"{TEST_CLASS} source must define exactly {EXPECTED_TEST_COUNT} tests, observed {len(source_methods)}"
        )
    observed_methods = [case["method"] for case in test_cases]
    duplicates = sorted({name for name in observed_methods if observed_methods.count(name) > 1})
    if duplicates:
        findings.append(f"xcresult contains duplicate task test cases: {', '.join(duplicates)}")
    missing = sorted(set(source_methods) - set(observed_methods))
    unexpected = sorted(set(observed_methods) - set(source_methods))
    if missing:
        findings.append(f"xcresult is missing source task tests: {', '.join(missing)}")
    if unexpected:
        findings.append(f"xcresult contains task tests absent from source: {', '.join(unexpected)}")
    if len(test_cases) != EXPECTED_TEST_COUNT:
        findings.append(f"xcresult must contain exactly {EXPECTED_TEST_COUNT} task test cases, observed {len(test_cases)}")
    not_passed = sorted(case["method"] for case in test_cases if case["result"] != "Passed")
    if not_passed:
        findings.append(f"task test cases not Passed: {', '.join(not_passed)}")
    return sorted(test_cases, key=lambda case: case["method"])


def required_screenshot_name(attachment_name: str) -> str | None:
    if attachment_name in REQUIRED_SCREENSHOTS:
        return attachment_name
    for name in REQUIRED_SCREENSHOTS:
        if not attachment_name.startswith(f"{name}_"):
            continue
        suffix = attachment_name[len(name) :]
        if XCODE_ATTACHMENT_SCREENSHOT_SUFFIX.fullmatch(suffix):
            return name
    return None


def export_and_validate_screenshots(
    *,
    tool: str,
    xcresult_path: Path,
    output_dir: Path,
    findings: list[str],
    image_decode_tool: str,
) -> tuple[str, list[dict[str, Any]]]:
    attachments_dir = output_dir / "attachments"
    screenshots_dir = output_dir / "screenshots"
    completed = subprocess.run(
        xcresult_command(
            tool,
            "export",
            "attachments",
            "--path",
            str(xcresult_path),
            "--output-path",
            str(attachments_dir),
        ),
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        findings.append(f"attachment export failed with exit {completed.returncode}: {detail}")
        return str(attachments_dir / "manifest.json"), []

    manifest_path = attachments_dir / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        findings.append(f"attachment manifest is unreadable: {error}")
        return str(manifest_path), []
    if not isinstance(manifest, list):
        findings.append("attachment manifest must be an array")
        return str(manifest_path), []
    secure_evidence_tree(attachments_dir)

    named: dict[str, list[tuple[Path, str]]] = {name: [] for name in REQUIRED_SCREENSHOTS}
    for test_entry in manifest:
        if not isinstance(test_entry, dict) or TEST_CLASS not in str(test_entry.get("testIdentifier", "")):
            continue
        test_identifier = str(test_entry.get("testIdentifier", ""))
        for attachment in test_entry.get("attachments", []):
            if not isinstance(attachment, dict):
                continue
            name = required_screenshot_name(
                str(attachment.get("suggestedHumanReadableName", ""))
            )
            exported_name = str(attachment.get("exportedFileName", ""))
            if name is not None and exported_name:
                exported_path = (attachments_dir / exported_name).resolve()
                if not path_within(exported_path, attachments_dir.resolve()):
                    findings.append(f"attachment export path escapes output directory: {exported_name}")
                    continue
                named[name].append((exported_path, test_identifier))

    screenshots_dir.mkdir(mode=0o700)
    exported: list[dict[str, Any]] = []
    for name in REQUIRED_SCREENSHOTS:
        matches = named[name]
        if len(matches) != 1:
            findings.append(f"required screenshot {name!r} must appear exactly once, observed {len(matches)}")
            continue
        source_path, test_identifier = matches[0]
        try:
            width, height = png_dimensions(source_path)
            verify_png_decode(source_path, image_decode_tool)
        except VerificationError as error:
            findings.append(f"required screenshot {name!r} is not a complete decodable PNG: {error}")
            continue
        destination = screenshots_dir / f"{name}.png"
        shutil.copyfile(source_path, destination)
        os.chmod(destination, 0o600)
        exported.append(
            {
                "name": name,
                "path": str(destination),
                "test_identifier": test_identifier,
                "width": width,
                "height": height,
                "sha256": sha256_file(destination),
            }
        )
    return str(manifest_path), exported


def write_report(
    report_path: Path,
    report: dict[str, Any],
    *,
    mode: int = 0o600,
) -> str:
    temporary_path = report_path.with_name(f".{report_path.name}.tmp-{os.getpid()}")
    descriptor: int | None = None
    payload = (json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
        "utf-8"
    )
    try:
        descriptor = os.open(
            temporary_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            mode,
        )
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = None
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(temporary_path, report_path)
        except FileExistsError as error:
            raise VerificationError(f"refusing to overwrite report output: {report_path}") from error
        if (report_path.stat().st_mode & 0o777) != mode:
            raise VerificationError(
                f"report output permissions must be {mode:04o}: {report_path}"
            )
    finally:
        if descriptor is not None:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)
    return hashlib.sha256(payload).hexdigest()


def capture_main(args: argparse.Namespace) -> int:
    try:
        verifier_sha256 = executed_verifier_sha256()
        toolchain = validated_toolchain(args)
        derived_data_root = resolve_input(
            args.derived_data_root,
            name="derived data root",
            kind="dir",
        )
        xctestrun_path = resolve_input(args.xctestrun, name="xctestrun", kind="file")
        app_path = resolve_input(args.app, name="target app", kind="dir")
        runner_path = resolve_input(args.runner, name="UI test runner", kind="dir")
        output_path = resolve_output(args.output)
        for label, path in (
            ("xctestrun", xctestrun_path),
            ("target app", app_path),
            ("UI test runner", runner_path),
            ("binding output", output_path),
        ):
            if not path_within(path, derived_data_root):
                raise VerificationError(f"{label} must be inside the component DerivedData root")
        if output_path.exists() or os.path.lexists(output_path):
            raise VerificationError(f"refusing to overwrite prepared artifact binding: {output_path}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        binding = capture_artifact_binding(
            xctestrun_path=xctestrun_path,
            app_path=app_path,
            runner_path=runner_path,
            codesign_tool=args.codesign_tool,
            captured_by_verifier_sha256=verifier_sha256,
            toolchain=toolchain if toolchain["mode"] == "trusted" else None,
        )
        binding_sha256 = write_report(output_path, binding, mode=0o400)
    except (OSError, VerificationError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(f"MVP.1 task artifact binding captured: {output_path}")
    print(f"MVP1_ARTIFACT_BINDING_SHA256={binding_sha256}")
    if toolchain["mode"] == "fixture":
        print("Fixture-only binding: trusted task evidence will reject this toolchain.")
    return 0


def main() -> int:
    args = parse_args()
    if args.mode == "capture":
        return capture_main(args)
    findings: list[str] = []
    derived_data_root = Path(args.derived_data_root).expanduser().resolve()
    output_dir = resolve_output(args.output_dir)
    try:
        verifier_executed_sha256 = executed_verifier_sha256()
        toolchain = validated_toolchain(args)
    except VerificationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if args.upstream_test_status < 0:
        print("error: upstream test status must be a non-negative integer", file=sys.stderr)
        return 2
    if not SHA256_PATTERN.fullmatch(args.expected_input_fingerprint):
        print("error: expected input fingerprint must be one lowercase SHA-256 value", file=sys.stderr)
        return 2
    if not COMMIT_PATTERN.fullmatch(args.expected_subject_commit):
        print("error: expected subject commit must be one lowercase 40-character Git hash", file=sys.stderr)
        return 2
    if not SHA256_PATTERN.fullmatch(args.expected_verifier_sha256):
        print("error: expected verifier SHA-256 must be one lowercase SHA-256 value", file=sys.stderr)
        return 2
    if not SHA256_PATTERN.fullmatch(args.expected_artifact_binding_sha256):
        print(
            "error: expected artifact binding SHA-256 must be one lowercase SHA-256 value",
            file=sys.stderr,
        )
        return 2
    if not derived_data_root.is_dir():
        print(f"error: derived data root is missing: {derived_data_root}", file=sys.stderr)
        return 2
    if not path_within(output_dir, derived_data_root):
        print("error: output directory must be inside the component DerivedData root", file=sys.stderr)
        return 2
    if output_dir.exists() or os.path.lexists(output_dir):
        print(f"error: refusing to overwrite existing evidence output: {output_dir}", file=sys.stderr)
        return 2

    try:
        repo_root = resolve_input(args.repo_root, name="repository root", kind="dir")
        verifier_source_path = resolve_input(
            args.verifier_source,
            name="verifier source",
            kind="file",
        )
        expected_verifier_source_path = (repo_root / "scripts" / "mvp1-task-xcresult.py").resolve()
        if verifier_source_path != expected_verifier_source_path:
            raise VerificationError(
                f"verifier source must be the canonical repository tool: {expected_verifier_source_path}"
            )
        verifier_snapshot_path = resolve_input(
            __file__,
            name="frozen verifier snapshot",
            kind="file",
        )
        if not path_within(verifier_snapshot_path, derived_data_root):
            raise VerificationError("frozen verifier snapshot must be inside component DerivedData")
        xcresult_path = resolve_input(args.xcresult, name="xcresult", kind="dir")
        if not path_within(xcresult_path, derived_data_root):
            raise VerificationError("xcresult must be inside the component DerivedData root")
        xctestrun_path = resolve_input(args.xctestrun, name="xctestrun", kind="file")
        if not path_within(xctestrun_path, derived_data_root):
            raise VerificationError("xctestrun must be inside the component DerivedData root")
        fingerprint_path = resolve_input(
            args.input_fingerprint_file,
            name="prepared input fingerprint",
            kind="file",
        )
        expected_fingerprint_path = (
            derived_data_root / ".meeting-assistant-xctestrun-inputs.sha256"
        ).resolve()
        if fingerprint_path != expected_fingerprint_path:
            raise VerificationError(
                f"prepared input fingerprint must use the component path {expected_fingerprint_path}"
            )
        source_path = resolve_input(args.test_source, name="task test source", kind="file")
        expected_source_path = (
            repo_root
            / "platform"
            / "native-app"
            / "UITests"
            / "MeetingAssistantNativeAppUITests"
            / "DesignedNativeShellAppBundleTests.swift"
        ).resolve()
        if source_path != expected_source_path:
            raise VerificationError(
                f"task test source must be the current repository suite: {expected_source_path}"
            )
        app_path = resolve_input(args.app, name="target app", kind="dir")
        runner_path = resolve_input(args.runner, name="UI test runner", kind="dir")
        artifact_binding_path = resolve_input(
            args.artifact_binding_file,
            name="prepared artifact binding",
            kind="file",
        )
        if not path_within(artifact_binding_path, derived_data_root):
            raise VerificationError(
                "prepared artifact binding must be inside the component DerivedData root"
            )
    except VerificationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    output_dir.mkdir(parents=True, mode=0o700)
    os.chmod(output_dir, 0o700)
    report_path = output_dir / "mvp1-task-xcresult-report.json"
    report: dict[str, Any] = {
        "schema_version": 2,
        "release_gate": "mvp1-task-xcresult-evidence",
        "passed": False,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "subject_commit": None,
        "subject_commit_before_test": args.expected_subject_commit,
        "task_subject_paths_clean": False,
        "current_input_fingerprint_after_test": None,
        "upstream_test_status": args.upstream_test_status,
        "toolchain": toolchain,
        "fixture_checks_passed": None,
        "os": {
            "system": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
        },
        "xcresult": {"path": str(xcresult_path)},
        "xctestrun": {"path": str(xctestrun_path)},
        "verifier_snapshot": {
            "path": str(verifier_snapshot_path),
            "source_path": str(verifier_source_path),
            "expected_sha256": args.expected_verifier_sha256,
            "executed_sha256": verifier_executed_sha256,
            "matched": verifier_executed_sha256 == args.expected_verifier_sha256,
        },
        "artifact_binding_file": {
            "path": str(artifact_binding_path),
            "expected_sha256": args.expected_artifact_binding_sha256,
            "observed_sha256": None,
            "sha256": None,
            "matched": False,
        },
        "artifact_binding_before_test": None,
        "prepared_input_fingerprint": None,
        "test_source": {"path": str(source_path), "class": TEST_CLASS, "methods": []},
        "summary": {},
        "tests": [],
        "app_identity": None,
        "runner_identity": None,
        "test_bundle_identity": None,
        "attachments": {
            "manifest_path": None,
            "required_screenshots": list(REQUIRED_SCREENSHOTS),
            "exported_screenshots": [],
        },
        "screenshot_visual_review": "pending",
        "findings": findings,
    }

    if args.upstream_test_status != 0:
        findings.append(
            f"upstream xcodebuild test-without-building exited with status {args.upstream_test_status}"
        )
    if verifier_executed_sha256 != args.expected_verifier_sha256:
        findings.append(
            "executed verifier snapshot SHA-256 does not match the pre-test frozen verifier SHA-256"
        )

    try:
        report["subject_commit"] = current_commit(repo_root, args.git_tool)
        if report["subject_commit"] != args.expected_subject_commit:
            findings.append(
                f"Git HEAD changed during task evidence collection: before "
                f"{args.expected_subject_commit}, after {report['subject_commit']}"
            )
        require_clean_task_subject(repo_root, args.git_tool)
        report["task_subject_paths_clean"] = True
        report["current_input_fingerprint_after_test"] = compute_current_input_fingerprint(
            repo_root=repo_root,
            destination=args.destination,
            git_tool=args.git_tool,
            xcodebuild_tool=args.xcodebuild_tool,
        )
        if report["current_input_fingerprint_after_test"] != args.expected_input_fingerprint:
            findings.append(
                "app/UI-test input fingerprint changed during task evidence collection"
            )
        expected_artifact_binding, artifact_binding_sha256 = read_artifact_binding(
            artifact_binding_path
        )
        report["artifact_binding_file"]["observed_sha256"] = artifact_binding_sha256
        report["artifact_binding_file"]["sha256"] = artifact_binding_sha256
        report["artifact_binding_file"]["matched"] = (
            artifact_binding_sha256 == args.expected_artifact_binding_sha256
        )
        if artifact_binding_sha256 != args.expected_artifact_binding_sha256:
            findings.append(
                "prepared artifact binding SHA-256 changed after its pre-test capture"
            )
        if (
            expected_artifact_binding.get("captured_by_verifier_sha256")
            != args.expected_verifier_sha256
        ):
            findings.append(
                "prepared artifact binding was not captured by the same frozen verifier snapshot"
            )
        observed_artifact_binding = capture_artifact_binding(
            xctestrun_path=xctestrun_path,
            app_path=app_path,
            runner_path=runner_path,
            codesign_tool=args.codesign_tool,
            captured_by_verifier_sha256=verifier_executed_sha256,
            toolchain=toolchain if toolchain["mode"] == "trusted" else None,
        )
        report["artifact_binding_before_test"] = expected_artifact_binding
        report["app_identity"] = observed_artifact_binding["app_identity"]
        report["runner_identity"] = observed_artifact_binding["runner_identity"]
        report["test_bundle_identity"] = observed_artifact_binding["test_bundle_identity"]
        report["xctestrun"] = observed_artifact_binding["xctestrun"]
        validate_artifact_binding(
            expected_artifact_binding,
            observed_artifact_binding,
            findings,
        )
        report["prepared_input_fingerprint"] = read_input_fingerprint(fingerprint_path)
        if report["prepared_input_fingerprint"] != args.expected_input_fingerprint:
            raise VerificationError(
                "prepared xctestrun fingerprint does not match the current app/test input fingerprint"
            )
        report["xcresult"] = {
            "path": str(xcresult_path),
            **directory_manifest(xcresult_path),
        }
        source_methods = source_test_methods(source_path)
        report["test_source"]["methods"] = source_methods
        summary = run_json(
            xcresult_command(
                args.xcresulttool,
                "get",
                "test-results",
                "summary",
                "--path",
                str(xcresult_path),
                "--compact",
            ),
            description="xcresult summary read",
        )
        report["summary"] = validate_summary(summary, findings)
        tests_payload = run_json(
            xcresult_command(
                args.xcresulttool,
                "get",
                "test-results",
                "tests",
                "--path",
                str(xcresult_path),
                "--compact",
            ),
            description="xcresult tests read",
        )
        report["tests"] = validate_tests(source_methods, flatten_test_cases(tests_payload), findings)
    except (OSError, VerificationError) as error:
        findings.append(str(error))

    try:
        manifest_path, screenshots = export_and_validate_screenshots(
            tool=args.xcresulttool,
            xcresult_path=xcresult_path,
            output_dir=output_dir,
            findings=findings,
            image_decode_tool=args.image_decode_tool,
        )
        report["attachments"]["manifest_path"] = manifest_path
        report["attachments"]["exported_screenshots"] = screenshots
    except (OSError, VerificationError) as error:
        findings.append(f"could not export task screenshots: {error}")

    os_fields = report["os"]
    if not all(os_fields.get(key) for key in ("system", "release", "machine")):
        findings.append("OS identity is incomplete")
    logical_checks_passed = not findings
    if toolchain["mode"] == "fixture":
        report["fixture_checks_passed"] = logical_checks_passed
    report["passed"] = logical_checks_passed and toolchain["mode"] == "trusted"
    write_report(report_path, report)
    print(f"MVP.1 task xcresult report: {report_path}")
    print("Screenshot visual review: pending")
    if findings:
        for finding in findings:
            print(f"error: {finding}", file=sys.stderr)
        return 1
    if toolchain["mode"] == "fixture":
        print(
            "error: fixture-mode verification completed, but fixture tools cannot produce passed=true evidence",
            file=sys.stderr,
        )
        return 1
    print("MVP.1 task xcresult evidence verified: 17 passed, 0 failed, 0 skipped, 0 expected failures.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
