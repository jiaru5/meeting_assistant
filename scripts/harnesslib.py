#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


class HarnessValidationError(Exception):
    pass


VALID_COMPONENT_TYPES = {"frontend", "backend", "worker", "platform"}
REQUIRED_COMPONENT_GATES = {"lint", "test", "build", "architecture", "security"}
REQUIRED_RELEASE_ARTIFACTS = {
    "threat_model",
    "slo",
    "runbook",
    "rollback_plan",
    "backup_restore_plan",
    "incident_response",
    "data_classification",
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise HarnessValidationError(f"missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise HarnessValidationError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise HarnessValidationError(f"{path} must contain a JSON object")
    return value


def project_mode(root: Path) -> str:
    status = root / "docs/product-spec/PROJECT-STATUS.md"
    text = status.read_text(encoding="utf-8")
    match = re.search(r"^\s*mode\s*:\s*(framework|adoption|project)\s*$", text, re.MULTILINE)
    if not match:
        raise HarnessValidationError(f"{status} must declare mode: framework, adoption, or project")
    return match.group(1)


def _require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _is_argv(value: Any) -> bool:
    if not (isinstance(value, list) and bool(value) and all(isinstance(item, str) and item for item in value)):
        return False
    executable = Path(value[0]).name
    if executable in {"true", "echo", "printf", ":"}:
        return False
    if executable in {"sh", "bash", "zsh"} and len(value) > 1 and value[1] == "-c":
        return False
    return True


def _inside_root(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as exc:
        raise HarnessValidationError(f"path escapes repository root: {relative}") from exc
    return path


def validate_agent_policy(root: Path) -> list[str]:
    policy = load_json(root / "harness/agent-policy.json")
    failures: list[str] = []
    _require(policy.get("schema_version") == 1, "agent policy schema_version must be 1", failures)
    _require(policy.get("default_profile") == "implementation", "default agent profile must be implementation", failures)

    profiles = policy.get("profiles")
    _require(isinstance(profiles, dict), "agent policy profiles must be an object", failures)
    if isinstance(profiles, dict):
        expected = {
            "analysis": ("read-only", "deny", "deny"),
            "implementation": ("workspace-write", "allowlist", "deny"),
            "release": ("read-only", "allowlist", "brokered"),
        }
        for name, (filesystem, network, credentials) in expected.items():
            profile = profiles.get(name)
            _require(isinstance(profile, dict), f"missing agent policy profile: {name}", failures)
            if isinstance(profile, dict):
                _require(profile.get("filesystem") == filesystem, f"{name} filesystem must be {filesystem}", failures)
                _require(profile.get("network") == network, f"{name} network must be {network}", failures)
                _require(
                    profile.get("production_credentials") == credentials,
                    f"{name} production_credentials must be {credentials}",
                    failures,
                )

    controls = policy.get("required_controls")
    _require(isinstance(controls, dict), "agent policy required_controls must be an object", failures)
    if isinstance(controls, dict):
        for name in (
            "least_privilege_tools",
            "network_egress_control",
            "auditable_sessions",
            "independent_release_approval",
            "cost_and_loop_limits",
        ):
            _require(controls.get(name) is True, f"agent required control must be true: {name}", failures)

    tool_policy = policy.get("tool_policy")
    _require(isinstance(tool_policy, dict), "agent tool_policy must be an object", failures)
    if isinstance(tool_policy, dict):
        _require(tool_policy.get("default") == "deny", "agent tool policy must default to deny", failures)
        _require(
            tool_policy.get("production_tools_in_implementation") is False,
            "implementation profile cannot use production tools",
            failures,
        )
        _require(
            isinstance(tool_policy.get("allowed_mcp_servers"), list),
            "allowed_mcp_servers must be an array",
            failures,
        )

    limits = policy.get("limits")
    _require(isinstance(limits, dict), "agent limits must be an object", failures)
    if isinstance(limits, dict):
        for name in ("max_session_minutes", "max_tool_calls", "max_consecutive_failures", "max_cost_usd"):
            value = limits.get(name)
            _require(isinstance(value, (int, float)) and value > 0, f"agent limit must be positive: {name}", failures)

    protected = policy.get("protected_paths")
    _require(isinstance(protected, list) and "docs/product-spec/" in protected, "product spec must be a protected path", failures)
    _require(
        isinstance(protected, list) and ".github/workflows/" in protected,
        "CI workflows must be a protected path",
        failures,
    )
    return failures


def discover_component_targets(root: Path) -> set[str]:
    targets: set[str] = set()
    for package in (root / "frontend/apps").glob("*/package.json"):
        targets.add(package.parent.relative_to(root).as_posix())
    for pom in (root / "backend/services").glob("*/pom.xml"):
        targets.add(pom.parent.relative_to(root).as_posix())
    for component in (root / "platform").glob("*/component.json"):
        targets.add(component.parent.relative_to(root).as_posix())
    return targets


def validate_manifest(root: Path, phase: str = "current") -> list[str]:
    manifest = load_json(root / "harness/project-manifest.json")
    failures: list[str] = []
    mode = project_mode(root)
    effective_phase = "development" if phase == "current" and mode == "project" else phase

    _require(manifest.get("schema_version") == 1, "project manifest schema_version must be 1", failures)
    project = manifest.get("project")
    _require(isinstance(project, dict), "project manifest project must be an object", failures)
    components = manifest.get("components")
    _require(isinstance(components, list), "project manifest components must be an array", failures)
    release_policy = manifest.get("release_policy")
    _require(isinstance(release_policy, dict), "project manifest release_policy must be an object", failures)

    registered_paths: set[str] = set()
    registered_component_paths: set[str] = set()
    component_ids: set[str] = set()
    production_components = 0
    if isinstance(components, list):
        for index, component in enumerate(components):
            prefix = f"components[{index}]"
            if not isinstance(component, dict):
                failures.append(f"{prefix} must be an object")
                continue
            component_id = component.get("id")
            component_type = component.get("type")
            relative_path = component.get("path")
            _require(isinstance(component_id, str) and bool(component_id), f"{prefix}.id is required", failures)
            _require(component_id not in component_ids, f"duplicate component id: {component_id}", failures)
            if isinstance(component_id, str):
                component_ids.add(component_id)
            _require(component_type in VALID_COMPONENT_TYPES, f"{prefix}.type is invalid", failures)
            _require(isinstance(relative_path, str) and bool(relative_path), f"{prefix}.path is required", failures)
            if isinstance(relative_path, str) and relative_path:
                try:
                    component_path = _inside_root(root, relative_path)
                    _require(component_path.is_dir(), f"registered component path does not exist: {relative_path}", failures)
                    registered_paths.add(Path(relative_path).as_posix())
                    if component_type in {"frontend", "backend", "worker", "platform"}:
                        registered_component_paths.add(Path(relative_path).as_posix())
                except HarnessValidationError as exc:
                    failures.append(str(exc))

            if component.get("production") is True:
                production_components += 1

            commands = component.get("commands")
            _require(isinstance(commands, dict), f"{prefix}.commands must be an object", failures)
            if isinstance(commands, dict) and effective_phase in {"development", "release"}:
                for gate in REQUIRED_COMPONENT_GATES:
                    _require(_is_argv(commands.get(gate)), f"{prefix}.commands.{gate} must be a non-empty argv array", failures)
                if component_type == "frontend":
                    _require(
                        _is_argv(commands.get("e2e")),
                        f"{prefix}.commands.e2e must be a non-empty argv array for frontend components",
                        failures,
                    )
                if component.get("production") is True:
                    _require(_is_argv(commands.get("sbom")), f"{prefix}.commands.sbom must be a non-empty argv array", failures)
                if component.get("requires_migrations") is True:
                    _require(
                        _is_argv(commands.get("migration")),
                        f"{prefix}.commands.migration must be set when requires_migrations is true",
                        failures,
                    )

            architecture_test = component.get("architecture_test")
            if effective_phase in {"development", "release"}:
                _require(
                    isinstance(architecture_test, str) and bool(architecture_test),
                    f"{prefix}.architecture_test is required",
                    failures,
                )
                if isinstance(architecture_test, str) and architecture_test:
                    _require(
                        _inside_root(root, architecture_test).is_file(),
                        f"architecture test does not exist: {architecture_test}",
                        failures,
                    )

            if component_type == "frontend" and isinstance(relative_path, str) and relative_path:
                package_path = root / relative_path / "package.json"
                _require(package_path.is_file(), f"frontend component requires package.json: {relative_path}", failures)
                lockfiles = ("package-lock.json", "pnpm-lock.yaml", "yarn.lock")
                _require(
                    any((root / relative_path / lockfile).is_file() for lockfile in lockfiles),
                    f"frontend component requires a lockfile: {relative_path}",
                    failures,
                )
            if component_type in {"backend", "worker"} and isinstance(relative_path, str) and relative_path:
                _require((root / relative_path / "pom.xml").is_file(), f"backend component requires pom.xml: {relative_path}", failures)
                _require((root / relative_path / "mvnw").is_file(), f"backend component requires Maven wrapper: {relative_path}", failures)

            dockerfile = component.get("dockerfile")
            if component.get("production") is True and effective_phase == "release":
                _require(isinstance(dockerfile, str) and bool(dockerfile), f"{prefix}.dockerfile is required for release", failures)
                if isinstance(dockerfile, str) and dockerfile:
                    docker_path = _inside_root(root, dockerfile)
                    _require(docker_path.is_file(), f"dockerfile does not exist: {dockerfile}", failures)
                    if docker_path.is_file():
                        docker_text = docker_path.read_text(encoding="utf-8")
                        from_lines = [
                            line.strip() for line in docker_text.splitlines() if line.strip().upper().startswith("FROM ")
                        ]
                        _require(bool(from_lines), f"dockerfile has no FROM instruction: {dockerfile}", failures)
                        for line in from_lines:
                            _require("@sha256:" in line, f"release Docker base image must be digest-pinned: {dockerfile}", failures)
                        user_lines = [
                            line.strip() for line in docker_text.splitlines() if line.strip().upper().startswith("USER ")
                        ]
                        _require(bool(user_lines), f"release Dockerfile must declare a non-root USER: {dockerfile}", failures)
                        if user_lines:
                            _require(
                                user_lines[-1].split(maxsplit=1)[1].strip() not in {"0", "root"},
                                f"release Dockerfile cannot run as root: {dockerfile}",
                                failures,
                            )

    if effective_phase in {"development", "release"}:
        _require(mode == "project", f"{effective_phase} checks require mode: project, found mode: {mode}", failures)
        _require(isinstance(components, list) and bool(components), "project mode requires registered components", failures)
        _require(production_components > 0, "project mode requires at least one production component", failures)
        discovered = discover_component_targets(root)
        _require(
            discovered == registered_component_paths,
            "all frontend/backend/platform component targets must be registered exactly once in harness/project-manifest.json "
            f"(discovered={sorted(discovered)}, registered={sorted(registered_component_paths)})",
            failures,
        )
        if isinstance(project, dict):
            _require(project.get("name") not in {"", "HARNESS_STARTER"}, "project.name must be replaced before project mode", failures)
            _require(project.get("owner") not in {"", "UNASSIGNED"}, "project.owner must be assigned before project mode", failures)
        full_stack = manifest.get("full_stack_e2e")
        if isinstance(full_stack, dict) and "pre_start_command" in full_stack:
            _require(
                _is_argv(full_stack.get("pre_start_command")),
                "full_stack_e2e.pre_start_command must be a non-empty argv array when set",
                failures,
            )

    if phase == "release":
        if isinstance(release_policy, dict):
            for name in (
                "require_project_mode",
                "require_registered_components",
                "require_full_stack_e2e",
                "require_security_gate",
                "require_supply_chain_gate",
                "require_production_readiness",
                "require_codeowners",
                "require_human_approval",
            ):
                _require(release_policy.get(name) is True, f"release policy must enable {name}", failures)
        codeowners = root / ".github/CODEOWNERS"
        _require(codeowners.is_file(), "release requires .github/CODEOWNERS", failures)
        if codeowners.is_file():
            codeowners_text = codeowners.read_text(encoding="utf-8")
            _require(
                bool(re.search(r"^\s*[^#\s].+@\S+", codeowners_text, re.MULTILINE)),
                ".github/CODEOWNERS must contain at least one ownership rule",
                failures,
            )

        full_stack = manifest.get("full_stack_e2e")
        _require(isinstance(full_stack, dict), "full_stack_e2e must be an object", failures)
        if isinstance(full_stack, dict):
            _require(
                isinstance(full_stack.get("compose_files"), list) and bool(full_stack.get("compose_files")),
                "release requires full_stack_e2e.compose_files",
                failures,
            )
            _require(
                isinstance(full_stack.get("services"), list) and bool(full_stack.get("services")),
                "release requires full_stack_e2e.services",
                failures,
            )
            _require(_is_argv(full_stack.get("test_command")), "release requires full_stack_e2e.test_command", failures)
            for compose_file in full_stack.get("compose_files", []):
                if isinstance(compose_file, str):
                    compose_path = _inside_root(root, compose_file)
                    _require(compose_path.is_file(), f"compose file does not exist: {compose_file}", failures)
                    if compose_path.is_file():
                        for line_number, line in enumerate(
                            compose_path.read_text(encoding="utf-8").splitlines(),
                            start=1,
                        ):
                            stripped = line.strip()
                            if stripped.startswith("image:"):
                                _require(
                                    "@sha256:" in stripped,
                                    f"release Compose image must be digest-pinned: {compose_file}:{line_number}",
                                    failures,
                                )

        readiness = manifest.get("production_readiness")
        _require(isinstance(readiness, dict), "production_readiness must be an object", failures)
        if isinstance(readiness, dict):
            for name in REQUIRED_RELEASE_ARTIFACTS:
                value = readiness.get(name)
                _require(isinstance(value, str) and bool(value), f"production readiness artifact is required: {name}", failures)
                if isinstance(value, str) and value:
                    artifact = _inside_root(root, value)
                    _require(artifact.is_file(), f"production readiness artifact does not exist: {value}", failures)
                    if artifact.is_file():
                        text = artifact.read_text(encoding="utf-8")
                        _require(
                            not re.search(r"\b(TODO|TBD|PLACEHOLDER)\b", text, re.IGNORECASE),
                            f"production readiness artifact contains unresolved placeholder: {value}",
                            failures,
                        )

        supply_chain = manifest.get("supply_chain")
        _require(isinstance(supply_chain, dict), "supply_chain must be an object", failures)
        if isinstance(supply_chain, dict):
            _require(
                supply_chain.get("provenance_target") in {"slsa-build-l2", "slsa-build-l3"},
                "release provenance_target must be slsa-build-l2 or slsa-build-l3",
                failures,
            )
            _require(
                supply_chain.get("sbom_format") == "cyclonedx-json",
                "release sbom_format must be cyclonedx-json",
                failures,
            )
            _require(
                supply_chain.get("artifact_signing") in {"keyless-oidc", "organization-kms"},
                "release artifact_signing must be keyless-oidc or organization-kms",
                failures,
            )

    failures.extend(validate_agent_policy(root))
    return failures


def manifest(root: Path) -> dict[str, Any]:
    return load_json(root / "harness/project-manifest.json")
