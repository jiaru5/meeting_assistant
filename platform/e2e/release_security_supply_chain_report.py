#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


EXPECTED_PROVIDER_MARKERS = {
    "real_dependency_json": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "real check_dependencies JSON accepted for runtime/model/hardware/no-auto-download."
    ),
    "runtime_local_path": "VS-MA-22 release-provider smoke [non-contract]: runtime .local path accepted:",
    "model_sha256": "VS-MA-22 release-provider smoke [non-contract]: model sha256 evidence verified",
    "model_license": "VS-MA-22 release-provider smoke [non-contract]: model license sidecar accepted:",
    "model_provenance": "VS-MA-22 release-provider smoke [non-contract]: model provenance sidecar accepted:",
    "model_local_path": "VS-MA-22 release-provider smoke [non-contract]: model .local large-v3 evidence path accepted:",
    "audio_fixture_local_path": (
        "VS-MA-22 release-provider smoke [non-contract]: mixed-language fixture .local path accepted:"
    ),
    "local_machine_scope": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "sidecar evidence is local-machine evidence only and does not prove all developer machines."
    ),
    "whisper_cpp_smoke": "whisper.cpp smoke passed.",
    "required_runtime_smoke": (
        "VS-MA-22 release-provider smoke [non-contract]: required whisper.cpp runtime smoke passed."
    ),
    "no_auto_download_upload": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "no-auto-download/no-auto-upload boundary remains unchanged."
    ),
    "pass_marker": "release provider smoke passed.",
}

EXPECTED_SECURITY_VALUES = {
    "report_schema": 1,
    "release_gate": "validation-only",
    "sast_static_analysis": True,
    "sca_dependency_review": True,
    "secret_scan": True,
    "forbidden_network_or_install_scan": True,
    "no_auto_downloads": True,
    "external_network_access": False,
    "packages_runtime_or_model": False,
    "findings": [],
}

EXPECTED_SUPPLY_CHAIN_VALUES = {
    "report_schema": 1,
    "release_gate": "validation-only",
    "sbom_format": "cyclonedx-json",
    "first_party_license": "Apache-2.0",
    "packaged_third_party_runtime_components": "none",
    "sca_dependency_review": True,
    "license_review": True,
    "packages_runtime_or_model": False,
    "auto_downloads": False,
    "provenance_scope": "validation-only",
    "release_provenance_attestation": "not-produced",
    "findings": [],
}

RELEASE_SCOPE_RESIDUAL_RISKS = [
    "does not prove signed or notarized macOS release distribution",
    "does not produce release provenance attestation or SLSA evidence",
    "does not prove runtime/model/audio sidecars on all developer machines",
    "does not prove real ScreenCaptureKit capture or native UI release bundle flows",
    "does not prove PV-MA-* release readiness or VS-MA-23 entry",
]


def _load_json(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except OSError as exc:
        return None, f"{path}: {exc.__class__.__name__}"
    except json.JSONDecodeError as exc:
        return None, f"{path}: invalid JSON ({exc.__class__.__name__})"


def _production_components(root: Path) -> list[dict[str, str]]:
    manifest_path = root / "harness/project-manifest.json"
    payload, error = _load_json(manifest_path)
    if error is not None or not isinstance(payload, dict):
        return []
    components: list[dict[str, str]] = []
    for component in payload.get("components", []):
        if not isinstance(component, dict) or component.get("production") is not True:
            continue
        component_id = component.get("id")
        component_path = component.get("path")
        if isinstance(component_id, str) and isinstance(component_path, str):
            components.append({"id": component_id, "path": component_path})
    return components


def _validate_component_report(
    root: Path,
    component: dict[str, str],
    *,
    report_kind: str,
    expected_values: dict[str, Any],
    relative_path: str,
) -> tuple[dict[str, Any], list[str]]:
    report_path = root / component["path"] / relative_path
    result: dict[str, Any] = {
        "component": component["id"],
        "path": str(report_path),
        "present": report_path.is_file(),
        "passed": False,
    }
    findings: list[str] = []
    if not report_path.is_file():
        findings.append(f"missing {report_kind} report for {component['id']}: {report_path.relative_to(root)}")
        return result, findings
    report, error = _load_json(report_path)
    if error is not None or not isinstance(report, dict):
        findings.append(f"invalid {report_kind} report for {component['id']}: {error or 'not a JSON object'}")
        return result, findings
    result["report"] = report
    if report.get("component") != component["id"]:
        findings.append(f"{report_kind} report for {component['id']} must bind component id")
    for key, expected in expected_values.items():
        if report.get(key) != expected:
            findings.append(
                f"{report_kind} report for {component['id']} must set {key}={expected!r}"
            )
    result["passed"] = not findings
    return result, findings


def build_report(
    root: Path,
    *,
    security_output_path: Path,
    supply_chain_output_path: Path,
    provider_output_path: Path,
    report_path: Path | None = None,
    security_exit_code: int = 0,
    supply_chain_exit_code: int = 0,
    provider_exit_code: int = 0,
    release_scope: bool = False,
) -> dict[str, Any]:
    root = root.resolve(strict=False)
    provider_output = provider_output_path.read_text(encoding="utf-8")
    provider_marker_results = {
        key: marker in provider_output for key, marker in EXPECTED_PROVIDER_MARKERS.items()
    }
    missing_provider_markers = [
        key for key, present in provider_marker_results.items() if not present
    ]
    traceback_seen = "Traceback" in provider_output

    findings: list[str] = []
    if security_exit_code != 0:
        findings.append(f"security-check exited {security_exit_code}")
    if supply_chain_exit_code != 0:
        findings.append(f"supply-chain-check exited {supply_chain_exit_code}")
    if provider_exit_code != 0:
        findings.append(f"release-provider-smoke exited {provider_exit_code}")
    if missing_provider_markers:
        findings.append(f"missing release-provider markers: {', '.join(missing_provider_markers)}")
    if traceback_seen:
        findings.append("release-provider output contained a traceback")

    components = _production_components(root)
    if not components:
        findings.append("no production components found in harness/project-manifest.json")

    security_reports: list[dict[str, Any]] = []
    supply_chain_reports: list[dict[str, Any]] = []
    for component in components:
        security_result, security_findings = _validate_component_report(
            root,
            component,
            report_kind="security",
            expected_values=EXPECTED_SECURITY_VALUES,
            relative_path="security/security-report.json",
        )
        supply_chain_result, supply_chain_findings = _validate_component_report(
            root,
            component,
            report_kind="supply-chain",
            expected_values=EXPECTED_SUPPLY_CHAIN_VALUES,
            relative_path="supply-chain/supply-chain-report.json",
        )
        security_reports.append(security_result)
        supply_chain_reports.append(supply_chain_result)
        findings.extend(security_findings)
        findings.extend(supply_chain_findings)

    passed = not findings
    report: dict[str, Any] = {
        "report_schema": 1,
        "component": "platform/e2e/release-security-supply-chain-smoke",
        "scope": "validation-only",
        "release_gate": "release-scope-security-supply-chain" if release_scope else "partial-evidence-only",
        "release_scope_security_supply_chain": release_scope,
        "vs_ma": ["VS-MA-22"],
        "pv": ["PV-MA-005", "PV-MA-007"],
        "related_pv": ["PV-MA-009", "PV-MA-011", "PV-MA-012"],
        "sec_ma": ["SEC-MA-001", "SEC-MA-003", "SEC-MA-004"],
        "security_output_path": str(security_output_path),
        "supply_chain_output_path": str(supply_chain_output_path),
        "provider_output_path": str(provider_output_path),
        "security_exit_code": security_exit_code,
        "supply_chain_exit_code": supply_chain_exit_code,
        "provider_exit_code": provider_exit_code,
        "passed": passed,
        "provider_marker_results": provider_marker_results,
        "missing_provider_markers": missing_provider_markers,
        "traceback_seen": traceback_seen,
        "security_reports": security_reports,
        "supply_chain_reports": supply_chain_reports,
        "not_release_readiness": True,
        "release_blockers": RELEASE_SCOPE_RESIDUAL_RISKS,
        "findings": findings,
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.environ.get("REPO_ROOT", "."))
    parser.add_argument("--security-output", required=True)
    parser.add_argument("--supply-chain-output", required=True)
    parser.add_argument("--provider-output", required=True)
    parser.add_argument("--report", default=os.environ.get("MA_SECURITY_SUPPLY_CHAIN_REPORT"))
    parser.add_argument("--security-exit-code", type=int, required=True)
    parser.add_argument("--supply-chain-exit-code", type=int, required=True)
    parser.add_argument("--provider-exit-code", type=int, required=True)
    parser.add_argument("--release-scope", action="store_true")
    args = parser.parse_args(argv)

    report = build_report(
        Path(args.root),
        security_output_path=Path(args.security_output),
        supply_chain_output_path=Path(args.supply_chain_output),
        provider_output_path=Path(args.provider_output),
        report_path=Path(args.report) if args.report else None,
        security_exit_code=args.security_exit_code,
        supply_chain_exit_code=args.supply_chain_exit_code,
        provider_exit_code=args.provider_exit_code,
        release_scope=args.release_scope,
    )
    if args.report:
        print(f"security supply-chain report: {args.report}", file=sys.stderr)
    print(
        "VS-MA-22 security supply-chain report marker [non-contract]: "
        f"report_schema={report['report_schema']} release_gate={report['release_gate']}."
    )
    if args.release_scope and report["passed"]:
        print("VS-MA-22 release-scope security supply-chain gate passed.")
    if report["passed"]:
        return 0
    for finding in report["findings"]:
        print(f"security supply-chain report failed: {finding}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
