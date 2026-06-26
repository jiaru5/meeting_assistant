#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from harnesslib import HarnessValidationError, manifest, project_mode, validate_manifest


ROOT = Path(os.environ.get("HARNESS_ROOT", Path(__file__).resolve().parent.parent)).resolve()


def fail_validation(phase: str) -> None:
    failures = validate_manifest(ROOT, phase)
    if failures:
        print(f"harness manifest validation failed for phase={phase}:", file=sys.stderr)
        for failure in failures:
            print(f" - {failure}", file=sys.stderr)
        raise SystemExit(1)


def run_argv(argv: list[str], cwd: Path, label: str) -> None:
    print(f"==> {label}: {' '.join(argv)}")
    subprocess.run(argv, cwd=cwd, check=True)


def components() -> list[dict[str, Any]]:
    value = manifest(ROOT).get("components", [])
    return [item for item in value if isinstance(item, dict)]


def run_gate(gate: str) -> None:
    mode = project_mode(ROOT)
    fail_validation("development" if mode == "project" else "current")
    selected = [component for component in components() if gate in component.get("commands", {})]
    if not selected:
        if gate == "e2e" and mode == "project" and not any(
            component.get("type") == "frontend" for component in components()
        ):
            print("e2e skipped: project has no registered frontend component.")
            return
        if mode == "project":
            print(f"{gate} failed: no registered component command.", file=sys.stderr)
            raise SystemExit(1)
        print(f"{gate} skipped: mode={mode}; no registered component command.")
        return
    for component in selected:
        run_argv(
            component["commands"][gate],
            ROOT / component["path"],
            f"{gate} for {component['id']}",
        )


def migration_check() -> None:
    mode = project_mode(ROOT)
    fail_validation("development" if mode == "project" else "current")
    selected = [component for component in components() if component.get("requires_migrations") is True]
    if not selected:
        if mode == "project":
            print("migration check: no registered component requires migrations.")
        else:
            print(f"migration check skipped: mode={mode}; no registered migration target.")
        return
    for component in selected:
        run_argv(
            component["commands"]["migration"],
            ROOT / component["path"],
            f"migration check for {component['id']}",
        )


def full_stack_e2e() -> None:
    mode = project_mode(ROOT)
    if mode != "project":
        print(f"full-stack e2e skipped: mode={mode}; project runtime is not initialized.")
        return
    fail_validation("development")
    config = manifest(ROOT).get("full_stack_e2e", {})
    compose_files = config.get("compose_files", [])
    services = config.get("services", [])
    test_command = config.get("test_command", [])
    if not compose_files or not services or not test_command:
        print(
            "full-stack e2e failed: project mode requires compose_files, services, and test_command "
            "in harness/project-manifest.json.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    if shutil.which("docker") is None:
        print("full-stack e2e failed: docker is required.", file=sys.stderr)
        raise SystemExit(1)

    compose = ["docker", "compose"]
    for compose_file in compose_files:
        compose.extend(["-f", compose_file])
    env = os.environ.copy()
    try:
        run_argv(compose + ["config", "--quiet"], ROOT, "validate Compose configuration")
        run_argv(compose + ["up", "--detach", "--wait"] + services, ROOT, "start isolated full stack")
        seed_command = config.get("seed_command", [])
        if seed_command:
            run_argv(seed_command, ROOT, "seed full-stack test data")
        run_argv(test_command, ROOT, "run full-stack E2E")
    finally:
        if config.get("cleanup", True):
            subprocess.run(compose + ["down", "--volumes", "--remove-orphans"], cwd=ROOT, env=env, check=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--phase", choices=("current", "development", "release"), default="current")

    gate_parser = subparsers.add_parser("run-gate")
    gate_parser.add_argument("gate", choices=("lint", "test", "e2e", "build", "architecture", "security", "sbom"))

    subparsers.add_parser("migration-check")
    subparsers.add_parser("full-stack-e2e")
    args = parser.parse_args()

    try:
        if args.command == "check":
            fail_validation(args.phase)
            print(f"harness manifest check passed: phase={args.phase}, mode={project_mode(ROOT)}.")
        elif args.command == "run-gate":
            run_gate(args.gate)
        elif args.command == "migration-check":
            migration_check()
        elif args.command == "full-stack-e2e":
            full_stack_e2e()
    except (HarnessValidationError, subprocess.CalledProcessError) as exc:
        print(f"harness runtime failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
