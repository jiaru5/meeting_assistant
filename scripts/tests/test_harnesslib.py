from __future__ import annotations

import base64
import json
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import importlib.util
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harnesslib import validate_agent_policy, validate_manifest  # noqa: E402


def load_adoption_runtime():
    spec = importlib.util.spec_from_file_location("adoption_runtime", ROOT / "scripts/adoption-runtime.py")
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def load_task_xcresult_verifier():
    spec = importlib.util.spec_from_file_location(
        "mvp1_task_xcresult",
        ROOT / "scripts/mvp1-task-xcresult.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class HarnessValidationTests(unittest.TestCase):
    def create_native_app_bundle_xctestrun_fixture(
        self,
        derived_data: Path,
        *,
        include_app: bool = True,
        include_runner: bool = True,
        include_fingerprint: bool = False,
    ) -> None:
        products = derived_data / "Build/Products"
        products.mkdir(parents=True, exist_ok=True)
        xctestrun = products / "MeetingAssistantNative_test.xctestrun"
        xctestrun.write_bytes(
            plistlib.dumps(
                {
                    "MeetingAssistantNativeAppUITests": {
                        "EnvironmentVariables": {},
                        "TestingEnvironmentVariables": {},
                    }
                }
            )
        )

        if include_app:
            executable = products / "Debug/MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative"
            executable.parent.mkdir(parents=True, exist_ok=True)
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)

        if include_runner:
            runner = products / "Debug/MeetingAssistantNativeAppUITests-Runner.app/Contents/MacOS/MeetingAssistantNativeAppUITests-Runner"
            runner.parent.mkdir(parents=True, exist_ok=True)
            runner.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            runner.chmod(0o755)

        if include_fingerprint:
            verifier = load_task_xcresult_verifier()
            fingerprint = verifier.compute_current_input_fingerprint(
                repo_root=ROOT,
                destination="platform=macOS",
                git_tool="/usr/bin/git",
                xcodebuild_tool="/usr/bin/xcodebuild",
            )
            (derived_data / ".meeting-assistant-xctestrun-inputs.sha256").write_text(
                fingerprint + "\n",
                encoding="utf-8",
            )

    def run_native_app_bundle_script(
        self,
        derived_data: Path,
        overrides: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "MA_NATIVE_APP_DERIVED_DATA_PATH": str(derived_data),
                "MA_NATIVE_APP_REUSE_XCTESTRUN": "1",
                "MA_NATIVE_APP_PREPARE_ONLY": "0",
                "MA_NATIVE_APP_TASK_XCUITEST": "0",
                "MA_NATIVE_APP_REAL_CAPTURE_SMOKE": "0",
                "MA_NATIVE_APP_REAL_PROCESSING_SMOKE": "0",
                "MA_NATIVE_APP_REAL_ACTION_SMOKE": "0",
                "MA_NATIVE_APP_REAL_ACTION_OS_SMOKE": "0",
                "MA_NATIVE_APP_REAL_RUNTIME_SMOKE": "0",
                "MA_NATIVE_APP_VSMA21_HARDENING_SMOKE": "0",
                "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE": "0",
                "MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE": "0",
                "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE": "0",
                "MA_NATIVE_APP_TCC_IDENTITY_DIAGNOSTICS": "0",
            }
        )
        env.pop("MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY", None)
        env.pop("MA_NATIVE_APP_TERMINATE_STALE_INSTANCES", None)
        if overrides:
            env.update(overrides)
        return subprocess.run(
            ["bash", str(ROOT / "platform/native-app/scripts/test-app-bundle.sh")],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def copy_repo_fixture(self, directory: str) -> Path:
        fixture = Path(directory) / "repo"
        shutil.copytree(
            ROOT,
            fixture,
            ignore=shutil.ignore_patterns(
                ".git",
                ".harness",
                "__pycache__",
                "build",
                "example-smart_team-harness_engineering",
            ),
        )
        return fixture

    def test_copy_repo_fixture_excludes_ignored_build_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)

            self.assertEqual(list(fixture.glob("platform/*/build")), [])

    def test_prod_config_check_ignores_generated_platform_build_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            generated_output = fixture / "platform/native-app/build/generated-config.txt"
            generated_output.parent.mkdir(parents=True)
            generated_output.write_text("DEV_CURRENT=true\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/prod-config-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_prod_config_check_still_rejects_non_generated_platform_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            source_file = fixture / "platform/native-app/generated-config.txt"
            source_file.write_text("DEV_CURRENT=true\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/prod-config-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("production config surface contains dev-only settings", result.stderr)

    def init_git_baseline(self, fixture: Path) -> None:
        subprocess.run(["git", "init", "-b", "main"], cwd=fixture, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "Harness Test"], cwd=fixture, check=True)
        subprocess.run(["git", "config", "user.email", "harness@example.test"], cwd=fixture, check=True)
        subprocess.run(["git", "add", "."], cwd=fixture, check=True, capture_output=True, text=True)
        subprocess.run(["git", "commit", "-m", "baseline"], cwd=fixture, check=True, capture_output=True, text=True)

    def worktree_fingerprint(self, fixture: Path) -> str:
        return subprocess.check_output(
            [sys.executable, str(fixture / "scripts/worktree-fingerprint.py")],
            cwd=fixture,
            text=True,
        ).strip()

    def write_evidence_step(
        self,
        fixture: Path,
        scope: str,
        step: str,
        fingerprint: str,
        exit_code: int = 0,
        command: str | None = None,
    ) -> None:
        evidence_dir = fixture / ".harness/evidence" / scope
        evidence_dir.mkdir(parents=True, exist_ok=True)
        log = evidence_dir / f"{step}.log"
        meta = evidence_dir / f"{step}.meta"
        relative_log = f".harness/evidence/{scope}/{step}.log"
        log.write_text(f"{step} evidence\n", encoding="utf-8")
        meta.write_text(
            "\n".join(
                [
                    f"step={step}",
                    f"exit_code={exit_code}",
                    f"worktree_fingerprint={fingerprint}",
                    f"command={command or f'./scripts/{step}.sh'}",
                    f"log={relative_log}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

    def security_report_command(
        self,
        marker: Path | None = None,
        overrides: dict[str, object] | None = None,
        write_report: bool = True,
    ) -> list[str]:
        marker_code = ""
        if marker is not None:
            marker_code = f"Path({str(marker)!r}).open('a').write('security\\n'); "
        report_code = ""
        if write_report:
            report_code = (
                "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                "Path('security').mkdir(exist_ok=True); "
                "report = {"
                "'component': component['id'], "
                "'report_schema': 1, "
                "'release_gate': 'validation-only', "
                "'sast_static_analysis': True, "
                "'sca_dependency_review': True, "
                "'secret_scan': True, "
                "'forbidden_network_or_install_scan': True, "
                "'no_auto_downloads': True, "
                "'external_network_access': False, "
                "'packages_runtime_or_model': False, "
                "'findings': []"
                "}; "
                f"report.update({repr(overrides or {})}); "
                "Path('security/security-report.json').write_text(json.dumps(report), encoding='utf-8'); "
            )
        return [
            sys.executable,
            "-c",
            "import json; from pathlib import Path; " + report_code + marker_code,
        ]

    def supply_chain_report_command(
        self,
        marker: Path | None = None,
        overrides: dict[str, object] | None = None,
        write_report: bool = True,
    ) -> list[str]:
        marker_code = ""
        if marker is not None:
            marker_code = f"Path({str(marker)!r}).open('a').write('sbom\\n'); "
        report_code = ""
        if write_report:
            report_code = (
                "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                "sbom = json.loads(next(Path('sbom').glob('*.cdx.json')).read_text(encoding='utf-8')); "
                "sbom_name = sbom['metadata']['component']['name']; "
                "Path('supply-chain').mkdir(exist_ok=True); "
                "report = {"
                "'component': component['id'], "
                "'report_schema': 1, "
                "'release_gate': 'validation-only', "
                "'sbom_format': 'cyclonedx-json', "
                "'sbom': sbom_name, "
                "'first_party_license': 'Apache-2.0', "
                "'packaged_third_party_runtime_components': 'none', "
                "'sca_dependency_review': True, "
                "'license_review': True, "
                "'packages_runtime_or_model': False, "
                "'auto_downloads': False, "
                "'provenance_scope': 'validation-only', "
                "'release_provenance_attestation': 'not-produced', "
                "'findings': []"
                "}; "
                f"report.update({repr(overrides or {})}); "
                "Path('supply-chain/supply-chain-report.json').write_text(json.dumps(report), encoding='utf-8'); "
            )
        return [
            sys.executable,
            "-c",
            "import json; from pathlib import Path; " + report_code + marker_code,
        ]

    def write_release_supply_chain_reports(
        self,
        reports_dir: Path,
        manifest: dict,
        head: str,
        digest: str,
        *,
        provenance_digest: str | None = None,
        signature_digest: str | None = None,
    ) -> tuple[Path, Path, Path, Path]:
        reports_dir.mkdir()
        provenance_digest = provenance_digest or digest
        signature_digest = signature_digest or digest
        bundle_path = reports_dir / "bundle.json"
        provenance_path = reports_dir / "provenance.json"
        signature_path = reports_dir / "signature.json"
        sidecar_path = reports_dir / "sidecar.json"
        sidecar_target_smoke_path = reports_dir / "sidecar-target-smoke.json"
        attestation_path = reports_dir / "release-provenance.intoto.dsse.json"
        signature_bundle_path = reports_dir / "release-signature.sigstore-bundle.json"
        attestation_statement = {
            "_type": "https://in-toto.io/Statement/v1",
            "subject": [
                {
                    "name": "MeetingAssistantNative.app",
                    "digest": {"sha256": provenance_digest.split(":", 1)[1]},
                }
            ],
            "predicateType": "https://slsa.dev/provenance/v1",
            "predicate": {
                "buildDefinition": {
                    "buildType": "https://github.com/example/meeting_assistant/.github/workflows/release.yml",
                    "externalParameters": {"repository": "example/meeting_assistant"},
                },
                "runDetails": {"builder": {"id": "github-actions-oidc"}},
            },
        }
        attestation_payload = base64.b64encode(json.dumps(attestation_statement).encode("utf-8")).decode("ascii")
        attestation_path.write_text(
            json.dumps(
                {
                    "payloadType": "application/vnd.in-toto+json",
                    "payload": attestation_payload,
                    "signatures": [{"keyid": "sigstore-keyless", "sig": "MEUCIQDfixture"}],
                }
            ),
            encoding="utf-8",
        )
        signature_bundle_path.write_text(
            json.dumps(
                {
                    "mediaType": "application/vnd.dev.sigstore.bundle+json;version=0.3",
                    "verificationMaterial": {"tlogEntries": [{"logIndex": 7}]},
                    "messageSignature": {"messageDigest": {"algorithm": "SHA2_256"}},
                }
            ),
            encoding="utf-8",
        )
        attestation_digest = "sha256:" + hashlib.sha256(attestation_path.read_bytes()).hexdigest()
        signature_bundle_digest = "sha256:" + hashlib.sha256(signature_bundle_path.read_bytes()).hexdigest()
        bundle_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-bundle",
                    "subject_commit": head,
                    "builder": "github-actions-oidc",
                    "source_repository": "example/meeting_assistant",
                    "bundle": {
                        "name": "MeetingAssistantNative.zip",
                        "artifact_type": "macos-app-archive",
                        "archive_format": "zip",
                        "app_bundle": "MeetingAssistantNative.app",
                        "build_configuration": "Release",
                        "code_signed": True,
                        "distribution_mode": "developer-id",
                        "install_method": "developer-id-zip",
                        "packages_runtime_or_model": False,
                        "auto_downloads": False,
                        "contains_meeting_data": False,
                        "digest": digest,
                    },
                }
            ),
            encoding="utf-8",
        )
        provenance_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "provenance_target": manifest["supply_chain"]["provenance_target"],
                    "release_provenance_attestation": "produced",
                    "sbom_format": manifest["supply_chain"]["sbom_format"],
                    "subject_commit": head,
                    "builder": "github-actions-oidc",
                    "source_repository": "example/meeting_assistant",
                    "attestation": {
                        "format": "dsse-in-toto-slsa-provenance-v1",
                        "predicate_type": "https://slsa.dev/provenance/v1",
                        "path": str(attestation_path),
                        "digest": attestation_digest,
                    },
                    "artifacts": [{"name": "MeetingAssistantNative.app", "digest": provenance_digest}],
                }
            ),
            encoding="utf-8",
        )
        signature_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "artifact_signing": manifest["supply_chain"]["artifact_signing"],
                    "signing_status": "signed",
                    "subject_commit": head,
                    "verifier": "cosign",
                    "signed_artifacts": [
                        {
                            "name": "MeetingAssistantNative.app",
                            "digest": signature_digest,
                            "signature_type": "keyless-oidc",
                            "certificate_identity": "https://github.com/example/meeting_assistant/.github/workflows/release.yml@refs/tags/v0.1.0",
                            "certificate_issuer": "https://token.actions.githubusercontent.com",
                            "transparency_log": {"log_id": "rekor", "log_index": 7},
                            "signature_bundle": {
                                "format": "sigstore-bundle-json",
                                "path": str(signature_bundle_path),
                                "digest": signature_bundle_digest,
                            },
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        runtime_artifact = {
            "name": "whisper-cli",
            "path": "/Users/runner/.local/bin/whisper-cli",
            "digest": digest,
            "source": "user-prepared-local-runtime",
        }
        model_artifact = {
            "name": "ggml-large-v3-turbo-q5_0.bin",
            "path": "/Users/runner/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin",
            "digest": digest,
            "source": "user-prepared-local-model",
            "license": "Apache-2.0",
            "provenance_ref": "/Users/runner/.local/share/ai-models/whisper.cpp/large-v3-turbo/provenance.json",
        }
        smoke_audio_fixture = {
            "name": "mixed-zh-en-tech.wav",
            "path": "/Users/runner/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav",
            "digest": digest,
            "source": "user-prepared-local-fixture",
        }
        target_smoke = {
            "check_dependencies_ok": True,
            "whisper_cpp_smoke_passed": True,
            "no_auto_downloads_observed": True,
        }
        sidecar_target_smoke_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-sidecar-target-smoke",
                    "subject_commit": head,
                    "target_id": "macos-arm64-ci",
                    "os": "macos",
                    "architecture": "arm64",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "artifacts": {
                        "runtime": {"name": runtime_artifact["name"], "digest": runtime_artifact["digest"]},
                        "model": {"name": model_artifact["name"], "digest": model_artifact["digest"]},
                        "smoke_audio_fixture": {
                            "name": smoke_audio_fixture["name"],
                            "digest": smoke_audio_fixture["digest"],
                        },
                    },
                    "smoke": target_smoke,
                }
            ),
            encoding="utf-8",
        )
        sidecar_target_smoke_digest = "sha256:" + hashlib.sha256(sidecar_target_smoke_path.read_bytes()).hexdigest()
        sidecar_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-sidecar-portability",
                    "target_scope": "all-target-machines",
                    "subject_commit": head,
                    "builder": "github-actions-oidc",
                    "source_repository": "example/meeting_assistant",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "target_machines": [
                        {
                            "target_id": "macos-arm64-ci",
                            "os": "macos",
                            "architecture": "arm64",
                            "runtime": runtime_artifact,
                            "model": model_artifact,
                            "smoke_audio_fixture": smoke_audio_fixture,
                            "smoke": target_smoke,
                            "smoke_report": {
                                "path": str(sidecar_target_smoke_path),
                                "digest": sidecar_target_smoke_digest,
                            },
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return bundle_path, provenance_path, signature_path, sidecar_path

    def test_framework_manifest_and_policy_are_valid(self) -> None:
        self.assertEqual([], validate_manifest(ROOT, "current"))
        self.assertEqual([], validate_agent_policy(ROOT))

    def test_framework_adoption_check_passes(self) -> None:
        result = subprocess.run(
            [str(ROOT / "scripts/adoption-check.sh")],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_docs_check_rejects_stale_project_activation_wording(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            product_readme = fixture / "docs/product-spec/README.md"
            product_readme.write_text(
                product_readme.read_text(encoding="utf-8")
                + "\n当前仓库处于 `adoption` 模式，等待用户 activation。\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/docs-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale adoption/spec-review or activation-pending wording", result.stderr + result.stdout)

    def test_docs_check_rejects_current_mode_restatement_outside_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            readme = fixture / "README.md"
            readme.write_text(
                readme.read_text(encoding="utf-8")
                + "\n当前项目处于 `project` 模式，可以直接实现业务代码。\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/docs-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("current project mode must only be declared", result.stderr + result.stdout)

    def test_docs_check_rejects_stale_activation_boundary_wording(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            platform_readme = fixture / "platform/README.md"
            platform_readme.write_text(
                platform_readme.read_text(encoding="utf-8")
                + "\n本目录只提供 activation 阶段的非业务 full-stack/E2E 替代计划。\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/docs-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale activation-boundary wording", result.stderr + result.stdout)

    def test_docs_check_rejects_capability_missing_acceptance_link(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            scope = fixture / "docs/product-spec/01-product-scope.md"
            scope.write_text(
                scope.read_text(encoding="utf-8").replace(
                    "`AC-MA-001` | `PV-MA-001`",
                    "`AC-MA-999` | `PV-MA-001`",
                    1,
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/docs-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("references missing acceptance rows", result.stderr + result.stdout)

    def test_docs_check_rejects_validation_row_without_capability_link(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            matrix = fixture / "docs/engineering/06-product-validation-matrix.md"
            matrix.write_text(
                matrix.read_text(encoding="utf-8").replace("`CAP-MA-001` ", "", 1),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/docs-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PV-MA-001 must reference at least one CAP-MA capability row", result.stderr + result.stdout)

    def test_readiness_parser_accepts_chinese_headers(self) -> None:
        adoption_runtime = load_adoption_runtime()
        rows = adoption_runtime.parse_readiness_tables(
            "\n".join(
                [
                    "| 分卷 | Project mode 前必需内容 | 状态 | 是否阻塞缺口 | 下一步 |",
                    "|---|---|---|---|---|",
                    "| `01-product-scope.md` | 产品范围 | ready | no |  |",
                    "| 领域 | Project mode 前必需内容 | 状态 | 是否阻塞缺口 | 下一步 |",
                    "|---|---|---|---|---|",
                    "| Validation matrix | PV 行 | partial | yes | 补测试 |",
                ]
            )
        )
        self.assertEqual("ready", adoption_runtime.row_status(rows["01-product-scope.md"]))
        self.assertFalse(adoption_runtime.row_is_blocking(rows["01-product-scope.md"]))
        self.assertEqual("partial", adoption_runtime.row_status(rows["validation matrix"]))
        self.assertTrue(adoption_runtime.row_is_blocking(rows["validation matrix"]))

    def write_validation_statuses(
        self,
        fixture: Path,
        default_status: str,
        overrides: dict[str, str] | None = None,
    ) -> None:
        overrides = overrides or {}
        matrix = fixture / "docs/engineering/06-product-validation-matrix.md"
        lines: list[str] = []
        for line in matrix.read_text(encoding="utf-8").splitlines():
            if line.startswith("| PV-"):
                identifier = line.split("|", 2)[1].strip()
                if identifier != "PV-AREA-001":
                    prefix, _, suffix = line.rsplit("|", 2)
                    line = f"{prefix}| `{overrides.get(identifier, default_status)}` |{suffix}"
            lines.append(line)
        matrix.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def write_local_functional_preflight_report(
        self,
        fixture: Path,
        *,
        subject_commit: str | None = None,
        target_scope: str = "local-machine-only",
        not_release_readiness: bool = True,
        passed: bool = True,
        findings: list[str] | None = None,
    ) -> Path:
        report_path = fixture / "local-functional-preflight.json"
        subject_commit = subject_commit or subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=fixture,
            text=True,
        ).strip()
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "local-direct-functional-preflight",
                    "target_scope": target_scope,
                    "subject_commit": subject_commit,
                    "target_id": "macos-arm64-local",
                    "passed": passed,
                    "not_release_readiness": not_release_readiness,
                    "release_blockers": [
                        "local-direct functional preflight does not run product-validation release or release-preflight"
                    ],
                    "local_direct_app": {
                        "path": "/Users/runner/Applications/MeetingAssistantNativeLocal.app",
                        "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                    },
                    "local_direct_app_source": {
                        "release_bundle_report": {
                            "path": "/repo/.harness/release-inputs/bundle/release-bundle-report.json",
                            "digest": "sha256:" + ("a" * 64),
                            "subject_commit": subject_commit,
                            "distribution_mode": "local-direct",
                            "bundle_digest": "sha256:" + ("b" * 64),
                            "archive_path": "/repo/.harness/release-inputs/bundle/MeetingAssistantNative-Release.zip",
                        },
                        "source_app": {
                            "path": "/repo/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app",
                            "executable_path": "/repo/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative",
                            "executable_sha256": "sha256:" + ("c" * 64),
                            "unsigned_executable_sha256": "sha256:" + ("e" * 64),
                        },
                        "installed_app": {
                            "path": "/Users/runner/Applications/MeetingAssistantNativeLocal.app",
                            "executable_path": "/Users/runner/Applications/MeetingAssistantNativeLocal.app/Contents/MacOS/MeetingAssistantNative",
                            "executable_sha256": "sha256:" + ("d" * 64),
                            "unsigned_executable_sha256": "sha256:" + ("e" * 64),
                            "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                        },
                        "source_and_installed_executable_match": True,
                        "source_and_installed_unsigned_executable_match": True,
                    },
                    "functional_checks": {
                        "launch_modes": ["open"],
                        "same_app_identity": True,
                        "stage_passed": {
                            "recording": True,
                            "processing": True,
                            "actions": True,
                        },
                        "expected_terms_found": ["HTTP", "LLM", "clean architecture"],
                        "actions_markers": [
                            "Copy complete.",
                            "Export complete.",
                            "Delete complete.",
                        ],
                    },
                    "findings": findings or [],
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def write_vs_statuses(
        self,
        fixture: Path,
        default_status: str,
        overrides: dict[str, str] | None = None,
    ) -> None:
        overrides = overrides or {}
        plan = fixture / "docs/engineering/07-development-plan.md"
        lines: list[str] = []
        for line in plan.read_text(encoding="utf-8").splitlines():
            match = re.match(r"^(\| `?(VS-MA-\d{2}[A-Z]?)`? \| )([^|]+)( \| .*)$", line)
            if match and match.group(3).strip() in {
                "已达退出口径",
                "partial evidence",
                "未进入 release-scope",
                "MVP 外",
            }:
                identifier = match.group(2)
                line = f"{match.group(1)}{overrides.get(identifier, default_status)}{match.group(4)}"
            lines.append(line)
        plan.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_product_validation_current_phase_accepts_documented_partial_rows(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/product-validation-check.py"), "current-phase"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("product validation current-phase passed", result.stdout)

    def test_product_validation_release_reports_concise_blockers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_validation_statuses(fixture, "covered", {"PV-MA-010": "planned"})

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            output = result.stderr + result.stdout
            self.assertIn("Release candidate requires every PV-* row to be `covered`.", output)
            self.assertIn("PV-MA-010: planned", output)
            self.assertNotIn("当前证据", output)

    def test_product_validation_release_rejects_partial_pv_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_validation_statuses(fixture, "covered", {"PV-MA-001": "partial"})

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            output = result.stderr + result.stdout
            self.assertIn("Release candidate requires every PV-* row to be `covered`.", output)
            self.assertIn("PV-MA-001: partial", output)

    def test_product_validation_local_functional_accepts_current_preflight_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            report = self.write_local_functional_preflight_report(fixture)
            env = os.environ.copy()
            env["MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"] = str(report)

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "local-functional"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("product validation local-functional passed", result.stdout)
            self.assertIn("Local functional scope is not release readiness", result.stdout)
            self.assertIn("covered=", result.stdout)

    def test_product_validation_local_functional_rejects_stale_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            report = self.write_local_functional_preflight_report(fixture, subject_commit="0" * 40)
            env = os.environ.copy()
            env["MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"] = str(report)

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "local-functional"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("subject_commit must bind current HEAD", result.stderr + result.stdout)

    def test_product_validation_local_functional_rejects_stale_installed_app_binding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            report = self.write_local_functional_preflight_report(fixture)
            payload = json.loads(report.read_text(encoding="utf-8"))
            payload["local_direct_app_source"]["source_and_installed_executable_match"] = False
            payload["local_direct_app_source"]["source_and_installed_unsigned_executable_match"] = False
            payload["local_direct_app_source"]["installed_app"]["unsigned_executable_sha256"] = "sha256:" + ("f" * 64)
            report.write_text(json.dumps(payload), encoding="utf-8")
            env = os.environ.copy()
            env["MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"] = str(report)

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "local-functional"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("installed app unsigned executable content matches the current source app", result.stderr + result.stdout)

    def test_product_validation_local_functional_reports_preflight_findings_without_schema_noise(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            report = self.write_local_functional_preflight_report(
                fixture,
                passed=False,
                findings=[
                    "local-direct-same-chain-smoke exited 1",
                    "release local-direct target smoke report must set passed=True",
                ],
            )
            payload = json.loads(report.read_text(encoding="utf-8"))
            payload.pop("local_direct_app_source")
            payload.pop("functional_checks")
            report.write_text(json.dumps(payload), encoding="utf-8")
            env = os.environ.copy()
            env["MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"] = str(report)

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "local-functional"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("local-functional report is not passing", output)
            self.assertIn("local-functional finding: local-direct-same-chain-smoke exited 1", output)
            self.assertNotIn("must include local_direct_app_source", output)
            self.assertNotIn("must include functional_checks", output)

    def test_product_validation_local_functional_rejects_release_scope_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            report = self.write_local_functional_preflight_report(
                fixture,
                target_scope="all-target-machines",
                not_release_readiness=False,
            )
            env = os.environ.copy()
            env["MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"] = str(report)

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "local-functional"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("target_scope='local-machine-only'", output)
            self.assertIn("not_release_readiness=True", output)

    def test_vs_stage_current_phase_accepts_documented_partial_rows(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/vs-stage-check.py"), "current-phase"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("VS-MA stage current-phase passed", result.stdout)

    def test_vs_stage_release_rejects_partial_prerequisite_vs_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_vs_statuses(
                fixture,
                "已达退出口径",
                {"VS-MA-21": "partial evidence", "VS-MA-23": "未进入 release-scope"},
            )

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/vs-stage-check.py"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Release candidate requires VS-MA-14 through VS-MA-22", output)
            self.assertIn("VS-MA-21: partial evidence", output)
            self.assertNotIn("VS-MA-22: partial evidence", output)
            self.assertNotIn("VS-MA-23: 未进入 release-scope", output)

    def test_vs_stage_release_passes_after_prerequisite_vs_rows_close(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_vs_statuses(fixture, "已达退出口径")

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/vs-stage-check.py"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("VS-MA stage release passed", result.stdout)

    def test_release_preflight_fails_closed_on_vs_prerequisites_before_pv(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_vs_statuses(
                fixture,
                "已达退出口径",
                {"VS-MA-21": "partial evidence", "VS-MA-23": "未进入 release-scope"},
            )

            result = subprocess.run(
                [str(fixture / "scripts/release-preflight.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Release candidate requires VS-MA-14 through VS-MA-22", output)
            self.assertIn("VS-MA-21: partial evidence", output)
            self.assertNotIn("VS-MA-22: partial evidence", output)
            self.assertIn("release-preflight failed: VS-MA release prerequisites are not closed", output)
            self.assertNotIn("product validation release failed", output)
            self.assertTrue((fixture / ".harness/evidence/release/production-readiness.meta").is_file())
            self.assertFalse((fixture / ".harness/evidence/release/docs.meta").exists())

    def test_release_preflight_fails_closed_when_pv_rows_are_partial(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_vs_statuses(fixture, "已达退出口径")
            self.write_validation_statuses(fixture, "covered", {"PV-MA-001": "partial"})

            result = subprocess.run(
                [str(fixture / "scripts/release-preflight.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Release candidate requires every PV-* row to be `covered`.", output)
            self.assertIn("PV-MA-001: partial", output)
            self.assertIn(
                "release-preflight failed: validation matrix contains non-covered release-scope PV-* rows",
                output,
            )
            self.assertNotIn("release-preflight passed.", output)
            self.assertTrue((fixture / ".harness/evidence/release/production-readiness.meta").is_file())
            self.assertFalse((fixture / ".harness/evidence/release/docs.meta").exists())

    def test_full_stack_smoke_does_not_emit_premature_vs_ma_23_release_marker(self) -> None:
        script = (ROOT / "platform/e2e/full-stack-smoke.sh").read_text(encoding="utf-8")
        readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertNotIn("VS-MA-23 provider/e2e release readiness", script)
        self.assertNotIn("VS-MA-23 provider/e2e release-readiness summary", readme)
        self.assertIn("VS-MA-21 provider/e2e hardening", script)
        self.assertIn("VS-MA-21/PV provider/e2e blocker reminder", script)
        self.assertIn("VS-MA-23 is not entered until VS-MA-21 and partial PV rows close", script)

    def test_phase_preflight_exposes_native_capture_opt_in_as_partial_evidence(self) -> None:
        phase_preflight = (ROOT / "scripts/phase-preflight.sh").read_text(encoding="utf-8")
        full_stack = (ROOT / "platform/e2e/full-stack-smoke.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")

        self.assertIn("./scripts/test-e2e-full-stack.sh", phase_preflight)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE", phase_preflight)
        self.assertIn("VS-MA-14/15 real native capture artifact smoke", phase_preflight)
        self.assertIn("partial evidence, not release readiness", phase_preflight)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE=1", full_stack)
        self.assertIn("./platform/e2e/native-capture-artifact-smoke.sh", full_stack)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE=1 ./scripts/phase-preflight.sh", dev_commands)
        self.assertIn("partial evidence", dev_commands)
        self.assertIn("release readiness", dev_commands)

    def test_release_preflight_registers_release_scope_native_capture_gate(self) -> None:
        release_preflight = (ROOT / "scripts/release-preflight.sh").read_text(encoding="utf-8")
        wrapper = (ROOT / "platform/e2e/release-native-capture-artifact-smoke.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn('MEETING_ASSISTANT_RELEASE_DISTRIBUTION_MODE:-local-direct', release_preflight)
        self.assertIn("run_local_direct_release_candidate_gates", release_preflight)
        self.assertIn("./scripts/release-candidate-inputs.py", release_preflight)
        self.assertIn("./platform/native-app/scripts/install-local-app.sh", release_preflight)
        self.assertIn("./platform/e2e/local-direct-functional-preflight.sh", release_preflight)
        self.assertIn("MA_LOCAL_DIRECT_FUNCTIONAL_BUILD_SOURCE=0", release_preflight)
        self.assertIn("./scripts/product-validation-check.py local-functional", release_preflight)
        self.assertIn("run_release_scope_native_capture_gates", release_preflight)
        self.assertIn("python3 scripts/vs-stage-check.py release", release_preflight)
        self.assertIn("python3 scripts/product-validation-check.py release", release_preflight)
        self.assertIn("./platform/e2e/release-native-capture-artifact-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-real-capture-same-chain-smoke.sh", release_preflight)
        self.assertLess(
            release_preflight.index("python3 scripts/vs-stage-check.py release"),
            release_preflight.index("python3 scripts/product-validation-check.py release"),
        )
        self.assertLess(
            release_preflight.index("python3 scripts/product-validation-check.py release"),
            release_preflight.index('if [ "$release_distribution_mode" = "local-direct" ]'),
        )
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE=1", wrapper)
        self.assertIn("MA_NATIVE_CAPTURE_RELEASE_SCOPE=1", wrapper)
        self.assertIn("./platform/e2e/native-capture-artifact-smoke.sh", wrapper)
        self.assertIn("release-scope-native-capture", dev_commands)
        self.assertIn("release-scope-native-capture", e2e_readme)
        self.assertIn("not_release_readiness=true", e2e_readme)

    def test_release_preflight_registers_release_scope_provider_hardening_gate(self) -> None:
        release_preflight = (ROOT / "scripts/release-preflight.sh").read_text(encoding="utf-8")
        wrapper = (ROOT / "platform/e2e/release-capture-processing-hardening-smoke.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn("run_local_direct_release_candidate_gates", release_preflight)
        self.assertIn("run_release_scope_native_capture_gates", release_preflight)
        self.assertIn("./platform/e2e/release-native-capture-artifact-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-real-capture-same-chain-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-native-ui-hardening-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-capture-processing-hardening-smoke.sh", release_preflight)
        self.assertLess(
            release_preflight.index('if [ "$release_distribution_mode" = "local-direct" ]'),
            release_preflight.index("./platform/e2e/release-capture-processing-hardening-smoke.sh"),
        )
        self.assertIn("platform/e2e/capture_processing_hardening_report.py", wrapper)
        self.assertIn("--release-scope", wrapper)
        self.assertIn("preserving capture-processing-smoke exit code", wrapper)
        self.assertIn("release-scope-provider-hardening", dev_commands)
        self.assertIn("release-scope-provider-hardening", e2e_readme)
        self.assertIn("not_release_readiness=true", e2e_readme)

    def test_release_preflight_registers_release_scope_native_ui_hardening_gate(self) -> None:
        release_preflight = (ROOT / "scripts/release-preflight.sh").read_text(encoding="utf-8")
        wrapper = (ROOT / "platform/e2e/release-native-ui-hardening-smoke.sh").read_text(encoding="utf-8")
        same_chain_wrapper = (ROOT / "platform/e2e/release-real-capture-same-chain-smoke.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn("run_release_scope_native_capture_gates", release_preflight)
        self.assertIn("./platform/e2e/release-native-capture-artifact-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-real-capture-same-chain-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-native-ui-hardening-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-capture-processing-hardening-smoke.sh", release_preflight)
        self.assertLess(
            release_preflight.index("./platform/e2e/release-native-capture-artifact-smoke.sh"),
            release_preflight.index("./platform/e2e/release-real-capture-same-chain-smoke.sh"),
        )
        self.assertLess(
            release_preflight.index("./platform/e2e/release-real-capture-same-chain-smoke.sh"),
            release_preflight.index("./platform/e2e/release-native-ui-hardening-smoke.sh"),
        )
        self.assertLess(
            release_preflight.index("./platform/e2e/release-native-ui-hardening-smoke.sh"),
            release_preflight.index("./platform/e2e/release-capture-processing-hardening-smoke.sh"),
        )
        self.assertIn("MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1", wrapper)
        self.assertIn("MA_NATIVE_APP_VSMA21_HARDENING_SMOKE=1", wrapper)
        self.assertIn("platform/e2e/release_native_ui_hardening_report.py", wrapper)
        self.assertIn("--release-scope", wrapper)
        self.assertIn("release-scope-real-capture-same-chain", same_chain_wrapper)
        self.assertIn("native_ui_same_chain_proven", same_chain_wrapper)
        self.assertIn("MA_REAL_CAPTURE_SAME_CHAIN_TRANSCRIPTION_RUNTIME", same_chain_wrapper)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE_AUDIO_PLAYBACK_PATH", same_chain_wrapper)
        self.assertIn("VS-MA-23 local real runtime same-chain marker", same_chain_wrapper)
        self.assertIn("release-scope-native-ui-hardening", dev_commands)
        self.assertIn("release-scope-real-capture-same-chain", dev_commands)
        self.assertIn("MA_REAL_CAPTURE_SAME_CHAIN_TRANSCRIPTION_RUNTIME=whisper_cpp", dev_commands)
        self.assertIn("release-scope-native-ui-hardening", e2e_readme)
        self.assertIn("release-scope-real-capture-same-chain", e2e_readme)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE_AUDIO_PLAYBACK_PATH", e2e_readme)
        self.assertIn("not_release_readiness=true", e2e_readme)

    def test_release_preflight_registers_release_scope_security_supply_chain_gate(self) -> None:
        release_preflight = (ROOT / "scripts/release-preflight.sh").read_text(encoding="utf-8")
        wrapper = (ROOT / "platform/e2e/release-security-supply-chain-smoke.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn("./platform/e2e/release-capture-processing-hardening-smoke.sh", release_preflight)
        self.assertIn("./platform/e2e/release-security-supply-chain-smoke.sh", release_preflight)
        self.assertIn("./scripts/test-e2e-full-stack.sh", release_preflight)
        self.assertLess(
            release_preflight.index("./platform/e2e/release-capture-processing-hardening-smoke.sh"),
            release_preflight.index("./platform/e2e/release-security-supply-chain-smoke.sh"),
        )
        self.assertLess(
            release_preflight.index("./platform/e2e/release-security-supply-chain-smoke.sh"),
            release_preflight.index("./scripts/test-e2e-full-stack.sh"),
        )
        self.assertIn("platform/e2e/release_security_supply_chain_report.py", wrapper)
        self.assertIn("./scripts/security-check.sh", wrapper)
        self.assertIn("./scripts/supply-chain-check.sh current", wrapper)
        self.assertIn("./platform/processing-cli/scripts/release-provider-smoke.sh", wrapper)
        self.assertIn("preserving release-provider-smoke exit code", wrapper)
        self.assertIn("release-scope-security-supply-chain", dev_commands)
        self.assertIn("release-scope-security-supply-chain", e2e_readme)
        self.assertIn("not_release_readiness=true", e2e_readme)
        self.assertIn(".harness/release-inputs/supply-chain/release-provenance-report.json", dev_commands)
        self.assertNotIn(".harness/evidence/release/supply-chain/release-provenance-report.json", dev_commands)

    def test_real_runtime_app_bundle_failures_always_refresh_structured_report(self) -> None:
        script = (ROOT / "platform/native-app/scripts/test-app-bundle.sh").read_text(encoding="utf-8")
        failure_block = script[
            script.index('echo "native-app real runtime app-bundle XCUITest failed.')
            : script.index('echo "native-app real runtime app-bundle XCUITest passed."')
        ]

        self.assertIn("write_ui_testing_automation_blocker_report", failure_block)
        self.assertIn("is_ui_testing_automation_blocked", failure_block)
        self.assertLess(
            failure_block.index("write_ui_testing_automation_blocker_report"),
            failure_block.index("if is_ui_testing_automation_blocked"),
        )
        self.assertIn("real-runtime-ui-automation-report.json", script)
        self.assertIn("MA_NATIVE_REAL_RUNTIME_DIAGNOSTIC_DIR", script)
        self.assertIn("real-runtime-diagnostics", script)
        self.assertIn("native_app_bundle_ui_automation_report.py", script)

    def test_app_bundle_xctestrun_reuse_defaults_to_fingerprinted_auto_mode(self) -> None:
        script = (ROOT / "platform/native-app/scripts/test-app-bundle.sh").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn('reuse_xctestrun="${MA_NATIVE_APP_REUSE_XCTESTRUN:-auto}"', script)
        self.assertIn(".meeting-assistant-xctestrun-inputs.sha256", script)
        self.assertIn("compute_xctestrun_input_fingerprint", script)
        self.assertIn("platform/native-app/App", script)
        self.assertIn("platform/native-app/Sources", script)
        self.assertIn("platform/native-app/UITests", script)
        self.assertIn("platform/native-app/MeetingAssistantNative.xcodeproj/project.pbxproj", script)
        self.assertIn('printf \'destination=%s\\n\' "$destination"', script)
        self.assertIn("auto-reusing existing xctestrun", script)
        self.assertIn("MA_NATIVE_APP_REUSE_XCTESTRUN=0", script)
        self.assertIn("fingerprint differs from the current checkout", script)
        self.assertIn("print_app_bundle_identity_diagnostics", script)
        self.assertIn("print_ui_test_runner_identity_diagnostics", script)
        self.assertIn("App bundle cdhash", script)
        self.assertIn("App bundle designated requirement", script)
        self.assertIn("UI test runner cdhash", script)
        self.assertIn("UI test runner designated requirement", script)
        self.assertIn("validate_prepared_app_bundle_artifacts", script)
        self.assertIn("handle_foreign_meeting_assistant_instances", script)
        self.assertIn('MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY:-fail', script)
        self.assertIn("will not stop it automatically", script)
        self.assertIn("MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY=terminate", script)
        self.assertIn("MA_NATIVE_APP_TERMINATE_STALE_INSTANCES", script)
        self.assertIn("/MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative", script)
        self.assertIn('prepare_only="${MA_NATIVE_APP_PREPARE_ONLY:-0}"', script)
        self.assertIn("prepared without starting UI automation", script)
        self.assertIn("MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS=0", script)
        self.assertIn("Test Case ('.*'|-\\[.*\\]) started", script)
        self.assertIn('prepare_xctestrun "full suite"', script)
        self.assertIn('run_app_bundle_test_without_building "full suite"', script)
        self.assertIn("MA_NATIVE_APP_REUSE_XCTESTRUN=auto", dev_commands)
        self.assertIn(".meeting-assistant-xctestrun-inputs.sha256", dev_commands)
        self.assertIn("反复弹 Screen Recording", dev_commands)
        self.assertIn("cdhash", dev_commands)
        self.assertIn("MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY=terminate", dev_commands)
        self.assertIn("MA_NATIVE_APP_PREPARE_ONLY=1", dev_commands)
        self.assertIn("其他正在运行的 MeetingAssistantNative", dev_commands)
        self.assertIn("MA_NATIVE_APP_REUSE_XCTESTRUN=auto", e2e_readme)
        self.assertIn("Debug ad-hoc rebuild", e2e_readme)

    def test_app_bundle_prepare_only_fails_when_target_app_or_ui_runner_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            missing_both = Path(temp_dir) / "missing-both"
            self.create_native_app_bundle_xctestrun_fixture(
                missing_both,
                include_app=False,
                include_runner=False,
                include_fingerprint=True,
            )
            missing_both_result = self.run_native_app_bundle_script(
                missing_both,
                {
                    "MA_NATIVE_APP_TASK_XCUITEST": "1",
                    "MA_NATIVE_APP_PREPARE_ONLY": "1",
                },
            )

            self.assertEqual(missing_both_result.returncode, 1, missing_both_result.stderr)
            self.assertIn("missing target app MeetingAssistantNative.app", missing_both_result.stderr)
            self.assertIn(
                "missing UI runner MeetingAssistantNativeAppUITests-Runner.app",
                missing_both_result.stderr,
            )

            missing_runner = Path(temp_dir) / "missing-runner"
            self.create_native_app_bundle_xctestrun_fixture(
                missing_runner,
                include_app=True,
                include_runner=False,
                include_fingerprint=True,
            )
            missing_runner_result = self.run_native_app_bundle_script(
                missing_runner,
                {
                    "MA_NATIVE_APP_TASK_XCUITEST": "1",
                    "MA_NATIVE_APP_PREPARE_ONLY": "1",
                },
            )

            self.assertEqual(missing_runner_result.returncode, 1, missing_runner_result.stderr)
            self.assertNotIn("missing target app MeetingAssistantNative.app", missing_runner_result.stderr)
            self.assertIn(
                "missing UI runner MeetingAssistantNativeAppUITests-Runner.app",
                missing_runner_result.stderr,
            )

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_full_app_bundle_suite_checks_foreign_instance_policy_before_testing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            derived_data = Path(temp_dir) / "derived-data"
            self.create_native_app_bundle_xctestrun_fixture(derived_data)

            result = self.run_native_app_bundle_script(
                derived_data,
                {"MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY": "invalid-test-policy"},
            )

            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY must be fail, terminate, or ignore", result.stderr)
            self.assertFalse((derived_data / "full-app-bundle-xcuitest.log").exists())

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_app_bundle_prepare_only_reports_target_and_runner_identity_without_testing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            derived_data = Path(temp_dir) / "derived-data"
            self.create_native_app_bundle_xctestrun_fixture(
                derived_data,
                include_fingerprint=True,
            )

            result = self.run_native_app_bundle_script(
                derived_data,
                {
                    "MA_NATIVE_APP_TASK_XCUITEST": "1",
                    "MA_NATIVE_APP_PREPARE_ONLY": "1",
                },
            )
            output = result.stdout + result.stderr

            self.assertEqual(result.returncode, 0, output)
            self.assertIn("Prepared app bundle path:", output)
            self.assertIn("Prepared UI test runner path:", output)
            self.assertIn("App bundle signature:", output)
            self.assertIn("App bundle team identifier:", output)
            self.assertIn("App bundle cdhash:", output)
            self.assertIn("App bundle designated requirement:", output)
            self.assertIn("UI test runner signature:", output)
            self.assertIn("UI test runner team identifier:", output)
            self.assertIn("UI test runner cdhash:", output)
            self.assertIn("UI test runner designated requirement:", output)
            self.assertFalse((derived_data / "task-workflow-app-bundle-xcuitest.log").exists())

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_full_app_bundle_suite_uses_test_without_building_and_preserves_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            derived_data = temp_path / "derived-data"
            self.create_native_app_bundle_xctestrun_fixture(derived_data)
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            xcodebuild_log = temp_path / "xcodebuild.log"
            fake_xcodebuild = fake_bin / "xcodebuild"
            fake_xcodebuild.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$MA_NATIVE_APP_TEST_XCODEBUILD_LOG\"\n"
                "if [ \"${1:-}\" = \"test-without-building\" ]; then\n"
                "  exit 37\n"
                "fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            fake_xcodebuild.chmod(0o755)

            result = self.run_native_app_bundle_script(
                derived_data,
                {
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', '')}",
                    "MA_NATIVE_APP_TEST_XCODEBUILD_LOG": str(xcodebuild_log),
                    "MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY": "ignore",
                },
            )
            calls = xcodebuild_log.read_text(encoding="utf-8")

            self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
            self.assertIn("test-without-building", calls)
            self.assertNotIn("-only-testing:", calls)
            self.assertNotIn("test -project", calls)

    def test_vs_ma_21_app_bundle_hardening_smoke_is_documented_and_explicit(self) -> None:
        script = (ROOT / "platform/native-app/scripts/test-app-bundle.sh").read_text(encoding="utf-8")
        fast_gate_script = (ROOT / "platform/native-app/scripts/test.sh").read_text(encoding="utf-8")
        app_bundle_tests = (
            ROOT
            / "platform/native-app/UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift"
        ).read_text(encoding="utf-8")
        native_tests = (
            ROOT
            / "platform/native-app/tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift"
        ).read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")

        self.assertIn("MA_NATIVE_APP_VSMA21_HARDENING_SMOKE", script)
        self.assertIn("MA_NATIVE_APP_REUSE_XCTESTRUN", script)
        self.assertIn("MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS", script)
        self.assertIn("run_app_bundle_test_without_building", script)
        self.assertIn("reset_xctestrun_smoke_env", script)
        self.assertIn(
            "testVSMA21AppBundleProcessingPathConflictRetryPreservesOriginalCaptureArtifactWhenExplicitlyEnabled",
            script,
        )
        self.assertLess(
            script.index("reset_xctestrun_smoke_env"),
            script.index('set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" "1"'),
        )
        self.assertIn("configure_host_ffmpeg_for_app_bundle", script)
        self.assertIn('set_xctestrun_env "$xctestrun_path" "MEETING_ASSISTANT_FFMPEG_PATH" "$ffmpeg_path"', script)
        same_chain_marker = script.index(
            'set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" "1"'
        )
        self.assertLess(
            same_chain_marker,
            script.index("configure_host_ffmpeg_for_app_bundle", same_chain_marker),
        )
        self.assertIn("MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE", script)
        self.assertIn(
            "testVSMA23RealScreenCaptureKitWhisperRuntimeTranscriptActionsSameChainWhenExplicitlyEnabled",
            script,
        )
        self.assertIn("real-capture-real-runtime-same-chain-app-bundle-smoke.log", script)
        self.assertIn("MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE", app_bundle_tests)
        self.assertIn("startSmokeAudioPlayback", app_bundle_tests)
        self.assertIn("MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME", app_bundle_tests)
        self.assertIn("MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE=1", dev_commands)
        self.assertIn("vs-ma-21-hardening-app-bundle-smoke.log", script)
        self.assertIn("vs-ma-21-hardening-ui-automation-report.json", script)
        self.assertIn('write_ui_testing_automation_blocker_report "VS-MA-21 hardening"', script)
        self.assertIn("path-conflict-then-success", app_bundle_tests)
        self.assertIn("path_conflict", app_bundle_tests)
        self.assertIn("mixedAudioChecksum", app_bundle_tests)
        self.assertIn("MA_NATIVE_APP_VSMA21_HARDENING_SMOKE=1", dev_commands)
        self.assertIn("VS-MA-21 app-bundle hardening smoke", dev_commands)
        self.assertIn("MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS=0", dev_commands)
        self.assertIn("MA_NATIVE_VSMA21_HARDENING_BRIDGE_SMOKE", fast_gate_script)
        self.assertIn("native-app VS-MA-21 hardening bridge smoke passed.", fast_gate_script)
        self.assertIn(
            "processRunnerWithVSMA21HardeningFixtureRetriesPathConflictPreservingCaptureArtifactWhenEnabled",
            native_tests,
        )
        self.assertIn("VS-MA-21 native-app hardening bridge marker", native_tests)
        self.assertIn("MA_NATIVE_VSMA21_HARDENING_BRIDGE_SMOKE=1", dev_commands)

    def test_vs_ma_23_local_direct_app_run_entrypoint_is_documented_and_guarded(self) -> None:
        script = (ROOT / "platform/native-app/scripts/run-local-app.sh").read_text(encoding="utf-8")
        install_script = (ROOT / "platform/native-app/scripts/install-local-app.sh").read_text(encoding="utf-8")
        permission_diagnostics_script = (
            ROOT / "platform/native-app/scripts/local-app-permission-diagnostics.sh"
        ).read_text(encoding="utf-8")
        smoke_script = (ROOT / "platform/native-app/scripts/local-direct-smoke.sh").read_text(encoding="utf-8")
        recording_smoke_script = (
            ROOT / "platform/native-app/scripts/local-direct-recording-smoke.sh"
        ).read_text(encoding="utf-8")
        processing_smoke_script = (
            ROOT / "platform/native-app/scripts/local-direct-processing-smoke.sh"
        ).read_text(encoding="utf-8")
        actions_smoke_script = (
            ROOT / "platform/native-app/scripts/local-direct-actions-smoke.sh"
        ).read_text(encoding="utf-8")
        same_chain_smoke_script = (
            ROOT / "platform/native-app/scripts/local-direct-same-chain-smoke.sh"
        ).read_text(encoding="utf-8")
        app_source = (ROOT / "platform/native-app/App/MeetingAssistantNativeApp.swift").read_text(encoding="utf-8")
        shell_source = (
            ROOT / "platform/native-app/Sources/MeetingAssistantNative/DesignedNativeShellView.swift"
        ).read_text(encoding="utf-8")
        architecture = (ROOT / "platform/native-app/scripts/architecture.sh").read_text(encoding="utf-8")
        architecture_doc = (ROOT / "platform/native-app/Tests/ArchitectureTest.md").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")
        matrix = (ROOT / "docs/engineering/06-product-validation-matrix.md").read_text(encoding="utf-8")

        self.assertIn("release-bundle-create.py", script)
        self.assertIn("--distribution-mode local-direct", script)
        self.assertIn("Contents/MacOS/MeetingAssistantNative", script)
        self.assertIn("MA_NATIVE_LOCAL_APP_LAUNCH_MODE", script)
        self.assertIn("launchctl setenv", script)
        self.assertIn("launchctl unsetenv", script)
        self.assertIn("open_args=(-n -W -F", script)
        self.assertIn("platform/e2e/ma-cli-local.sh", script)
        self.assertIn("MEETING_ASSISTANT_CLI_PATH", script)
        self.assertIn("MEETING_ASSISTANT_WORKSPACE", script)
        self.assertIn("MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME", script)
        self.assertIn("MEETING_ASSISTANT_TRANSCRIPTION_MODEL", script)
        self.assertIn("MA_NATIVE_PROCESSING_RUNTIME", script)
        self.assertIn("MA_NATIVE_PROCESSING_LANGUAGE", script)
        self.assertIn('MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-true}"', script)
        self.assertIn('MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"', script)
        self.assertIn("MA_NATIVE_LOCAL_APP_REQUIRE_REAL_RUNTIME", script)
        self.assertIn("MA_NATIVE_LOCAL_APP_DRY_RUN", script)
        self.assertIn("${#app_args[@]}", script)
        self.assertIn("unset MA_NATIVE_APP_XCTEST", script)
        self.assertNotIn("notarytool", script)
        self.assertNotIn("stapler", script)
        self.assertNotIn("cosign", script)
        self.assertIn("release-bundle-create.py", install_script)
        self.assertIn("--distribution-mode local-direct", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_PATH", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_APP_NAME", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_ID", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_NAME", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_DISPLAY_NAME", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SOURCE_APP", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_INSTALL_REPORT", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SIGNING_MODE", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SIGNING_KEYCHAIN", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SIGNING_PASSWORD_FILE", install_script)
        self.assertIn("Meeting Assistant Local Code Signing", install_script)
        self.assertIn("local-app-install-report.json", install_script)
        self.assertIn('"release_gate": "local-direct-app-install"', install_script)
        self.assertIn('"recommended_direct_recording_smoke_command"', install_script)
        self.assertIn('"direct_launch_diagnostic"', install_script)
        self.assertIn('"installed_app"', install_script)
        self.assertIn('"source_app_identity"', install_script)
        self.assertIn('"local_signing"', install_script)
        self.assertIn('"stable_tcc_identity"', install_script)
        self.assertIn("certificate root", install_script)
        self.assertIn("local_tcc_identity_strategy", install_script)
        self.assertIn("~/Applications/MeetingAssistantNativeLocal.app", install_script)
        self.assertIn("CFBundleIdentifier", install_script)
        self.assertIn("local.meeting-assistant.native", install_script)
        self.assertIn("local.meeting-assistant.native.localdirect", install_script)
        self.assertIn("CFBundleName", install_script)
        self.assertIn("MeetingAssistantNativeLocal", install_script)
        self.assertIn("Meeting Assistant Native Local", install_script)
        self.assertIn("codesign --force --deep --keychain", install_script)
        self.assertIn("security create-keychain", install_script)
        self.assertIn("security add-trusted-cert", install_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SIGNING_MODE=ad-hoc", install_script)
        self.assertIn("codesign --verify --deep --strict", install_script)
        self.assertIn("modifies tcc or system settings: false", install_script)
        self.assertIn("requires developer id or notarization: false", install_script)
        self.assertIn('"modifies_tcc_or_system_settings": False', install_script)
        self.assertIn('"requires_developer_id_or_notarization": False', install_script)
        self.assertIn('"not_release_readiness": True', install_script)
        self.assertNotIn("x-apple.systempreferences", install_script)
        self.assertNotIn("tccutil", install_script)
        self.assertNotIn("notarytool", install_script)
        self.assertNotIn("stapler", install_script)
        self.assertNotIn("cosign", install_script)
        self.assertIn("local-app-permission-diagnostics", permission_diagnostics_script)
        self.assertIn("local-app-install-report.json", permission_diagnostics_script)
        self.assertIn("local-direct-recording-smoke-report.json", permission_diagnostics_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_RECORDING_REPORT_SEARCH_ROOTS", permission_diagnostics_script)
        self.assertIn("release-local-direct-target-smoke", permission_diagnostics_script)
        self.assertIn('"recording_report_selection"', permission_diagnostics_script)
        self.assertIn('"release_gate": "local-app-permission-diagnostics"', permission_diagnostics_script)
        self.assertIn('"recommended_tcc_target"', permission_diagnostics_script)
        self.assertIn('"same_app_as_recording_smoke"', permission_diagnostics_script)
        self.assertIn('"screen_recording_permission_denied"', permission_diagnostics_script)
        self.assertIn('"latest_matching_direct_success_recording_report"', permission_diagnostics_script)
        self.assertIn('"latest_matching_open_permission_denied_recording_report"', permission_diagnostics_script)
        self.assertIn('"launchservices_tcc_attribution_suspected"', permission_diagnostics_script)
        self.assertIn("CFBundleDisplayName", permission_diagnostics_script)
        self.assertIn("local_tcc_identity_strategy", permission_diagnostics_script)
        self.assertIn('"user_action_required"', permission_diagnostics_script)
        self.assertIn('"recommended_direct_recording_smoke_command"', permission_diagnostics_script)
        self.assertIn('"direct_launch_diagnostic"', permission_diagnostics_script)
        self.assertIn('"modifies_tcc_or_system_settings": False', permission_diagnostics_script)
        self.assertIn('"requires_developer_id_or_notarization": False', permission_diagnostics_script)
        self.assertIn('"not_release_readiness": True', permission_diagnostics_script)
        self.assertNotIn("x-apple.systempreferences", permission_diagnostics_script)
        self.assertNotIn("tccutil", permission_diagnostics_script)
        self.assertNotIn("notarytool", permission_diagnostics_script)
        self.assertNotIn("stapler", permission_diagnostics_script)
        self.assertNotIn("cosign", permission_diagnostics_script)
        self.assertIn("run-local-app.sh", smoke_script)
        self.assertIn("local-app-ax.swift", smoke_script)
        self.assertIn("AXUIElementCreateApplication", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXWindowsAttribute", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("concreteWindows.isEmpty ? values : concreteWindows", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("return rawCandidates", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("return [app]", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("AXUIElementCopyElementAtPosition", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("windowCenterElement", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXFocusedWindowAttribute", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXMainWindowAttribute", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXRaiseAction", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXConfirmAction", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXFocusedAttribute", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn('stringAttribute(element, kAXRoleAttribute) == "AXWindow"', (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn('stringAttribute(element, kAXRoleAttribute) == "AXSheet"', (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("kAXPressAction", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("AXUIElementSetAttributeValue", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        self.assertIn("CGWindowListCopyWindowInfo", (ROOT / "platform/native-app/scripts/local-app-ax.swift").read_text(encoding="utf-8"))
        for app_window_smoke in (
            recording_smoke_script,
            processing_smoke_script,
            actions_smoke_script,
        ):
            self.assertIn("FRONTMOST_SCRIPT", app_window_smoke)
            self.assertIn("system_events_frontmost_retry", app_window_smoke)
            self.assertIn("System Events foreground recovery", app_window_smoke)
            self.assertIn('"window_recovery_attempts"', app_window_smoke)
        self.assertIn("local-direct-ui-smoke", smoke_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT", smoke_script)
        self.assertIn("local-direct-app-state-report.json", smoke_script)
        self.assertIn("local-direct-window-report.json", smoke_script)
        self.assertIn("verifies_app_state_report", smoke_script)
        self.assertIn("ma.recording.startButton", smoke_script)
        self.assertIn("ma.recording.stopButton", smoke_script)
        self.assertIn("ma.processing.startButton", smoke_script)
        self.assertIn("ma.processing.retryButton", smoke_script)
        self.assertIn("verifies_action_control_identifiers", smoke_script)
        self.assertIn("recording_setup_marker_for_request", smoke_script)
        self.assertIn("checked_recording_setup_text", smoke_script)
        self.assertIn(
            "System audio capture is requested; microphone capture is not requested for this run.",
            smoke_script,
        )
        self.assertIn('"opens_system_settings": False', smoke_script)
        self.assertIn('"starts_recording": False', smoke_script)
        self.assertIn('"requires_developer_id_or_notarization": False', smoke_script)
        self.assertIn("Ready to start recording.", smoke_script)
        self.assertIn(
            "Choose a recorded meeting before generating a transcript.",
            smoke_script,
        )
        self.assertIn("checked_recording_setup_text", architecture)
        self.assertIn("bring that exact PID front once and retry the unchanged helper", architecture_doc)
        self.assertNotIn("CGRequestScreenCaptureAccess", smoke_script)
        self.assertNotIn("AVCaptureDevice.requestAccess", smoke_script)
        self.assertNotIn("x-apple.systempreferences", smoke_script)
        self.assertIn("run-local-app.sh", recording_smoke_script)
        self.assertIn("local-direct-recording-smoke", recording_smoke_script)
        self.assertIn("AXIdentifier", recording_smoke_script)
        self.assertIn("AXPress", recording_smoke_script)
        self.assertIn("ma.recording.startButton", recording_smoke_script)
        self.assertIn("ma.recording.stopButton", recording_smoke_script)
        self.assertIn("identifier=ma.newRecording.readiness", recording_smoke_script)
        self.assertIn("identifier=ma.recording.startButton enabled=true", recording_smoke_script)
        self.assertIn("Recording in progress.", recording_smoke_script)
        self.assertIn("Recording saved.", recording_smoke_script)
        self.assertIn("identifier=ma.recording.artifact.screen_video.status", recording_smoke_script)
        self.assertIn("description=Screen recording, Ready.", recording_smoke_script)
        self.assertIn("identifier=ma.recording.artifact.mixed_audio.status", recording_smoke_script)
        self.assertIn("description=Meeting audio, Ready.", recording_smoke_script)
        self.assertIn("wait_for_marker(marker, min(timeout_seconds, 60))", recording_smoke_script)
        self.assertIn('"blocker_detail_summary"', recording_smoke_script)
        self.assertIn("Full UI tree is written to the report ui_tree path.", recording_smoke_script)
        self.assertIn("recording_request", recording_smoke_script)
        self.assertIn("permission_failure_details", recording_smoke_script)
        self.assertIn("tcc_identity_mismatch_hint", recording_smoke_script)
        self.assertIn("direct_launch_diagnostic_hint", recording_smoke_script)
        self.assertIn("launch_attribution_boundary", recording_smoke_script)
        self.assertIn("recording session path already exists", recording_smoke_script)
        self.assertIn("workspace_precondition", recording_smoke_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_AUDIO_GRACE_SECONDS", recording_smoke_script)
        self.assertIn("audio_playback_completed", recording_smoke_script)
        self.assertIn("wait_for_recording_audio", recording_smoke_script)
        self.assertIn('"starts_recording": True', recording_smoke_script)
        self.assertIn('"may_request_macos_permissions": True', recording_smoke_script)
        self.assertIn('"not_release_readiness": True', recording_smoke_script)
        self.assertNotIn("x-apple.systempreferences", recording_smoke_script)
        self.assertNotIn("tccutil", recording_smoke_script)
        self.assertNotIn("notarytool", recording_smoke_script)
        self.assertIn("run-local-app.sh", processing_smoke_script)
        self.assertIn("local-direct-processing-smoke", processing_smoke_script)
        self.assertIn("System Events", processing_smoke_script)
        self.assertIn("AXIdentifier", processing_smoke_script)
        self.assertIn("AXPress", processing_smoke_script)
        self.assertIn("ma.processing.startButton", processing_smoke_script)
        self.assertIn("identifier=ma.processing.startButton enabled=true", processing_smoke_script)
        self.assertIn("TRANSCRIPT READY", processing_smoke_script)
        self.assertIn("Processing complete.", processing_smoke_script)
        self.assertIn("Processing completed with transcript-only speaker labels.", processing_smoke_script)
        self.assertIn("ui_completion_marker_observed", processing_smoke_script)
        self.assertIn("artifact_completion_fallback", processing_smoke_script)
        self.assertIn("ui_completion_observation_error", processing_smoke_script)
        self.assertIn("Processing artifacts complete after UI completion marker became unavailable.", processing_smoke_script)
        self.assertIn("normalized_audio", processing_smoke_script)
        self.assertIn("transcript_text", processing_smoke_script)
        self.assertIn("speaker_labels", processing_smoke_script)
        self.assertIn("workspace_precondition", processing_smoke_script)
        self.assertIn("recording_input_boundary", processing_smoke_script)
        self.assertIn("launch_attribution_boundary", processing_smoke_script)
        self.assertIn('"starts_recording": False', processing_smoke_script)
        self.assertIn('"starts_processing": True', processing_smoke_script)
        self.assertIn('"may_request_macos_permissions": False', processing_smoke_script)
        self.assertIn('"requires_developer_id_or_notarization": False', processing_smoke_script)
        self.assertIn('"not_release_readiness": True', processing_smoke_script)
        self.assertNotIn("CGRequestScreenCaptureAccess", processing_smoke_script)
        self.assertNotIn("AVCaptureDevice.requestAccess", processing_smoke_script)
        self.assertNotIn("x-apple.systempreferences", processing_smoke_script)
        self.assertNotIn("tccutil", processing_smoke_script)
        self.assertNotIn("notarytool", processing_smoke_script)

        self.assertIn("ProcessingCLIDependencyCheckRunner(environment: environment)", app_source)
        self.assertIn("usesStaticDependencyFixture", app_source)
        self.assertIn("initialReadinessState", app_source)
        self.assertIn("Task { @MainActor in", app_source)
        self.assertIn("MeetingAssistantNativeMainWindow.shared.openMainWindow()", app_source)
        self.assertIn("NativeLocalAppKeyboardShortcutView", app_source)
        self.assertIn("NSEvent.addLocalMonitorForEvents(matching: .keyDown)", app_source)
        self.assertIn("event.modifierFlags.intersection(.deviceIndependentFlagsMask)", app_source)
        self.assertIn("startRecording()", app_source)
        self.assertIn("stopRecording()", app_source)
        self.assertIn("startProcessing()", app_source)
        self.assertIn("copyTranscript()", app_source)
        self.assertIn("exportTranscript()", app_source)
        self.assertIn("requestDelete()", app_source)
        self.assertIn("confirmDelete()", app_source)
        self.assertIn("final class MeetingAssistantNativeMainWindow", app_source)
        self.assertIn("private var windowController: NSWindowController", app_source)
        self.assertIn("NSHostingController(rootView: rootView)", app_source)
        self.assertIn("NSWindow(", app_source)
        self.assertIn("window.setAccessibilityElement(true)", app_source)
        self.assertIn("window.setAccessibilityRole(.window)", app_source)
        self.assertIn("window.setAccessibilitySubrole(.standardWindow)", app_source)
        self.assertIn('window.setAccessibilityTitle("Meeting Assistant Native")', app_source)
        self.assertIn("hostingController.view.setAccessibilityElement(true)", app_source)
        self.assertIn("hostingController.view.setAccessibilityRole(.group)", app_source)
        self.assertIn('hostingController.view.setAccessibilityLabel("Meeting Assistant")', app_source)
        self.assertIn('window.setFrameAutosaveName("meeting-assistant-main")', app_source)
        self.assertIn("window.makeKeyAndOrderFront(nil)", app_source)
        self.assertNotIn("NSApplicationDelegateAdaptor", app_source)
        self.assertNotIn("MeetingAssistantNativeAppDelegate", app_source)
        self.assertNotIn("applicationDidFinishLaunching", app_source)
        self.assertNotIn('WindowGroup("Meeting Assistant Native', app_source)
        self.assertIn("autoRefreshPreflightOnAppear", app_source)
        self.assertIn("self.workspaceURL = recordingWorkspaceURL", app_source)
        self.assertIn(".onChange(of: permissionViewModel.state)", shell_source)
        self.assertIn("synchronizeRecordingReadiness(readiness)", shell_source)
        self.assertIn("recordingViewModel.updateReadiness(", shell_source)
        self.assertIn("readiness.canStartRecording(", shell_source)
        self.assertIn(
            "captureMicrophoneAudio: coordinator.recordingDraft.captureMicrophoneAudio",
            shell_source,
        )
        self.assertIn("processingViewModel.updateReadiness(readiness)", shell_source)
        self.assertIn('.keyboardShortcut("r", modifiers: [.command, .option])', shell_source)
        self.assertIn('.keyboardShortcut("s", modifiers: [.command, .option])', shell_source)
        self.assertIn('.keyboardShortcut("p", modifiers: [.command, .option])', shell_source)
        self.assertIn('.keyboardShortcut("c", modifiers: [.command, .option])', shell_source)
        self.assertIn('.keyboardShortcut("e", modifiers: [.command, .option])', shell_source)
        self.assertIn('.keyboardShortcut("d", modifiers: [.command, .option])', shell_source)
        self.assertIn(
            "await permissionViewModel.refresh(workspaceURL: coordinator.workspaceURL)",
            shell_source,
        )
        self.assertIn("autoRefreshPreflightIfNeeded", shell_source)

        self.assertIn("run-local-app.sh", architecture)
        self.assertIn("install-local-app.sh", architecture)
        self.assertIn("local-app-permission-diagnostics.sh", architecture)
        self.assertIn("local-direct-smoke.sh", architecture)
        self.assertIn("local-direct-recording-smoke.sh", architecture)
        self.assertIn("local-direct-processing-smoke.sh", architecture)
        self.assertIn("local-direct-same-chain-smoke.sh", architecture)
        self.assertIn("VS-MA-23 local-direct app run boundary", architecture_doc)
        self.assertIn("LaunchServices `open -n -W -F`", architecture_doc)
        self.assertIn("LaunchServices/TCC attribution", architecture_doc)
        self.assertIn("path_conflict", architecture_doc)
        self.assertIn("prefer concrete `AXWindow` or `AXSheet` roots", architecture_doc)
        self.assertIn("raise focused or main AXWindow roots", architecture_doc)
        self.assertIn("scoped `launchctl setenv`", architecture_doc)
        self.assertIn("App.init", architecture_doc)
        self.assertIn("retained AppKit window controller", architecture_doc)
        self.assertIn("standard AX window role/title", architecture_doc)
        self.assertIn("auto-refresh Preflight once on first shell appearance", architecture_doc)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO=true", architecture_doc)
        self.assertIn("MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO=false", architecture_doc)
        self.assertIn("~/Applications/MeetingAssistantNativeLocal.app", architecture_doc)
        self.assertIn("local.meeting-assistant.native.localdirect", architecture_doc)
        self.assertIn("local-direct-app-install", architecture_doc)
        self.assertIn("local-app-permission-diagnostics", architecture_doc)
        self.assertIn("repo-owned `local-app-ax.swift` helper's CoreGraphics window check", architecture_doc)
        self.assertIn("AX exposes only application/root candidates", architecture_doc)
        self.assertIn("AXUIElementCopyElementAtPosition", architecture_doc)
        self.assertIn("menu-only", architecture_doc)
        self.assertIn("stable keyboard shortcuts", architecture_doc)
        self.assertIn("MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT", architecture_doc)
        self.assertIn("run-local-app.sh", dev_commands)
        self.assertIn("install-local-app.sh", dev_commands)
        self.assertIn("local-app-permission-diagnostics.sh", dev_commands)
        self.assertIn("local-direct-smoke.sh", dev_commands)
        self.assertIn("local-direct-recording-smoke.sh", dev_commands)
        self.assertIn("local-direct-processing-smoke.sh", dev_commands)
        self.assertIn("artifact_completion_fallback", architecture_doc)
        self.assertIn("local-direct-same-chain-smoke.sh", dev_commands)
        self.assertIn("run-local-app.sh", e2e_readme)
        self.assertIn("install-local-app.sh", e2e_readme)
        self.assertIn("local-app-permission-diagnostics.sh", e2e_readme)
        self.assertIn("local-direct-smoke.sh", e2e_readme)
        self.assertIn("local-direct-recording-smoke.sh", e2e_readme)
        self.assertIn("local-direct-processing-smoke.sh", e2e_readme)
        self.assertIn("local-direct-same-chain-smoke.sh", e2e_readme)
        self.assertIn("LaunchServices", dev_commands)
        self.assertIn("LaunchServices", e2e_readme)
        self.assertIn("direct launch diagnostic", dev_commands)
        self.assertIn("direct launch diagnostic", e2e_readme)
        self.assertIn("local-direct app run", matrix)
        self.assertIn("local-direct app install", matrix)
        self.assertIn("local-direct processing smoke", matrix)
        self.assertIn("local-app-install-report.json", matrix)
        self.assertIn("local-app-permission-diagnostics-report.json", matrix)
        self.assertIn("local-direct-actions-smoke-report.json", matrix)
        self.assertIn("local-direct-same-chain-smoke-report.json", matrix)
        self.assertIn("自动刷新 Preflight", matrix)
        self.assertIn("checked_recording_setup_text", matrix)
        self.assertIn("run-local-app.sh", actions_smoke_script)
        self.assertIn("local-direct-actions-smoke", actions_smoke_script)
        self.assertIn("AXIdentifier", actions_smoke_script)
        self.assertIn("AXPress", actions_smoke_script)
        self.assertIn("requested_export_path", actions_smoke_script)
        self.assertIn("actual_export_path", actions_smoke_script)
        self.assertIn("Exported markdown transcript to", actions_smoke_script)
        self.assertIn("Export path: ", actions_smoke_script)
        self.assertIn("exported_path_from_snapshot", actions_smoke_script)
        self.assertIn("ma.meetingDetail.technicalDetails", actions_smoke_script)
        self.assertIn("ma.transcriptAction.copyButton", actions_smoke_script)
        self.assertIn("ma.transcriptAction.exportButton", actions_smoke_script)
        self.assertIn("ma.transcriptAction.deleteButton", actions_smoke_script)
        self.assertIn("ma.transcriptAction.deleteConfirmButton", actions_smoke_script)
        self.assertIn("Transcript actions are ready.", actions_smoke_script)
        self.assertIn("Copy complete.", actions_smoke_script)
        self.assertIn("Export complete.", actions_smoke_script)
        self.assertIn("Delete complete.", actions_smoke_script)
        self.assertIn("pbpaste", actions_smoke_script)
        self.assertIn("NSSavePanel", actions_smoke_script)
        self.assertIn("workspace_precondition", actions_smoke_script)
        self.assertIn("actions_boundary", actions_smoke_script)
        self.assertIn('"starts_recording": False', actions_smoke_script)
        self.assertIn('"starts_processing": False', actions_smoke_script)
        self.assertIn('"uses_system_pasteboard": True', actions_smoke_script)
        self.assertIn('"uses_save_panel": True', actions_smoke_script)
        self.assertIn('"may_request_macos_permissions": False', actions_smoke_script)
        self.assertIn('"requires_developer_id_or_notarization": False', actions_smoke_script)
        self.assertIn('"not_release_readiness": True', actions_smoke_script)
        self.assertNotIn("CGRequestScreenCaptureAccess", actions_smoke_script)
        self.assertNotIn("AVCaptureDevice.requestAccess", actions_smoke_script)
        self.assertNotIn("x-apple.systempreferences", actions_smoke_script)
        self.assertNotIn("tccutil", actions_smoke_script)
        self.assertNotIn("notarytool", actions_smoke_script)
        self.assertIn("local-direct-actions-smoke.sh", architecture)
        self.assertIn("local-direct-actions-smoke.sh", dev_commands)
        self.assertIn("local-direct-actions-smoke.sh", e2e_readme)
        self.assertIn("system pasteboard", dev_commands)
        self.assertIn("system pasteboard", e2e_readme)
        self.assertIn("NSSavePanel", dev_commands)
        self.assertIn("NSSavePanel", e2e_readme)
        self.assertIn("local-direct-actions-smoke", architecture_doc)
        self.assertIn("run-local-app.sh", same_chain_smoke_script)
        self.assertIn("local-direct-same-chain-smoke", same_chain_smoke_script)
        self.assertIn("local-direct-recording-smoke.sh", same_chain_smoke_script)
        self.assertIn("local-direct-processing-smoke.sh", same_chain_smoke_script)
        self.assertIn("local-direct-actions-smoke.sh", same_chain_smoke_script)
        self.assertIn("local-direct-same-chain-smoke-report.json", same_chain_smoke_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_WORKSPACE", same_chain_smoke_script)
        self.assertIn("MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_AUDIO", same_chain_smoke_script)
        self.assertIn("stage_reports", same_chain_smoke_script)
        self.assertIn("same_chain_boundary", same_chain_smoke_script)
        self.assertIn("same_app_identity", same_chain_smoke_script)
        self.assertIn("launch_modes", same_chain_smoke_script)
        self.assertIn("requires_clean_app_processes", same_chain_smoke_script)
        self.assertIn('"starts_recording": True', same_chain_smoke_script)
        self.assertIn('"starts_processing": True', same_chain_smoke_script)
        self.assertIn('"uses_system_pasteboard": True', same_chain_smoke_script)
        self.assertIn('"uses_save_panel": True', same_chain_smoke_script)
        self.assertIn('"may_request_macos_permissions": True', same_chain_smoke_script)
        self.assertIn('"requires_developer_id_or_notarization": False', same_chain_smoke_script)
        self.assertIn('"not_release_readiness": True', same_chain_smoke_script)
        self.assertNotIn("x-apple.systempreferences", same_chain_smoke_script)
        self.assertNotIn("tccutil", same_chain_smoke_script)
        self.assertNotIn("notarytool", same_chain_smoke_script)
        self.assertNotIn("stapler", same_chain_smoke_script)
        self.assertNotIn("cosign", same_chain_smoke_script)
        self.assertIn("local-direct-same-chain-smoke", architecture_doc)
        self.assertIn("local functional same-chain evidence only", architecture_doc)

    def test_release_preflight_registers_release_bundle_gate_before_supply_chain(self) -> None:
        release_preflight = (ROOT / "scripts/release-preflight.sh").read_text(encoding="utf-8")
        release_bundle_create = (ROOT / "scripts/release-bundle-create.py").read_text(encoding="utf-8")
        release_candidate_inputs = (ROOT / "scripts/release-candidate-inputs.py").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        security_supply_chain = (ROOT / "docs/engineering/10-security-and-supply-chain.md").read_text(encoding="utf-8")
        production_readiness = (ROOT / "docs/engineering/11-production-readiness.md").read_text(encoding="utf-8")

        self.assertIn("./scripts/test-e2e-full-stack.sh", release_preflight)
        self.assertIn("./scripts/release-bundle-check.sh", release_preflight)
        self.assertIn("./scripts/supply-chain-check.sh release", release_preflight)
        self.assertLess(
            release_preflight.index("./scripts/test-e2e-full-stack.sh"),
            release_preflight.index("./scripts/release-bundle-check.sh"),
        )
        self.assertLess(
            release_preflight.index("./scripts/release-bundle-check.sh"),
            release_preflight.index("./scripts/supply-chain-check.sh release"),
        )
        self.assertIn("release bundle evidence", dev_commands)
        self.assertIn("codesign", dev_commands)
        self.assertIn("stapler", dev_commands)
        self.assertIn("spctl", dev_commands)
        self.assertIn("release-bundle-create.py", dev_commands)
        self.assertIn("release-candidate-inputs.py", dev_commands)
        self.assertIn("notarytool", release_bundle_create)
        self.assertIn("release-credential-check.py", release_bundle_create)
        self.assertIn("release-bundle-check.sh", release_bundle_create)
        self.assertIn("release-bundle-create.py", release_candidate_inputs)
        self.assertIn("release-inputs-report.py", release_candidate_inputs)
        self.assertIn("release-bundle-check.sh", release_candidate_inputs)
        self.assertIn("supply-chain-check.sh", release_candidate_inputs)
        self.assertIn("--verify-release-bundle", release_candidate_inputs)
        self.assertIn("MEETING_ASSISTANT_RELEASE_SIGNING_IDENTITY", dev_commands)
        self.assertIn("MEETING_ASSISTANT_NOTARYTOOL_PROFILE", dev_commands)
        self.assertIn("不得生成 SLSA/DSSE", security_supply_chain)
        self.assertIn("不能自行生成、伪造或降级 provenance/signature", security_supply_chain)
        self.assertIn("release-bundle-check.sh", production_readiness)
        self.assertIn("release-bundle-create.py", production_readiness)
        self.assertIn("release-candidate-inputs.py", production_readiness)
        self.assertIn("codesign", production_readiness)
        self.assertIn("stapler", production_readiness)
        self.assertIn("spctl", production_readiness)
        self.assertIn(".harness/release-inputs/bundle/release-bundle-report.json", production_readiness)
        self.assertNotIn(".harness/evidence/release/bundle/release-bundle-report.json", production_readiness)

    def test_release_sidecar_target_smoke_entrypoint_is_documented(self) -> None:
        wrapper = (ROOT / "platform/e2e/release-sidecar-target-smoke.sh").read_text(encoding="utf-8")
        report = (ROOT / "platform/e2e/release_sidecar_target_smoke_report.py").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        security_supply_chain = (ROOT / "docs/engineering/10-security-and-supply-chain.md").read_text(encoding="utf-8")
        production_readiness = (ROOT / "docs/engineering/11-production-readiness.md").read_text(encoding="utf-8")

        self.assertIn("./platform/processing-cli/scripts/release-provider-smoke.sh", wrapper)
        self.assertIn("release_sidecar_target_smoke_report.py", wrapper)
        self.assertIn("MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORT", wrapper)
        self.assertIn("release-sidecar-target-smoke", report)
        self.assertIn("not_release_readiness", report)
        self.assertIn("release-sidecar-target-smoke.sh", dev_commands)
        self.assertIn("release-sidecar-target-smoke", security_supply_chain)
        self.assertIn("release-sidecar-target-smoke.sh", production_readiness)

    def test_release_sidecar_portability_report_entrypoint_is_documented(self) -> None:
        wrapper = (ROOT / "platform/e2e/release-sidecar-portability-report.sh").read_text(encoding="utf-8")
        report = (ROOT / "platform/e2e/release_sidecar_portability_report.py").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        security_supply_chain = (ROOT / "docs/engineering/10-security-and-supply-chain.md").read_text(encoding="utf-8")
        production_readiness = (ROOT / "docs/engineering/11-production-readiness.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")

        self.assertIn("release_sidecar_portability_report.py", wrapper)
        self.assertIn("MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORTS", wrapper)
        self.assertIn("MA_RELEASE_SIDECAR_EXPECTED_TARGETS", wrapper)
        self.assertIn("release-sidecar-portability", report)
        self.assertIn("incomplete-target-set", report)
        self.assertIn("release-sidecar-portability-report.sh", dev_commands)
        self.assertIn("release-sidecar-portability", security_supply_chain)
        self.assertIn("release-sidecar-portability-report.sh", production_readiness)
        self.assertIn("release-sidecar-portability-report.sh", e2e_readme)

    def test_release_local_direct_repeatability_entrypoints_are_documented(self) -> None:
        target_wrapper = (ROOT / "platform/e2e/release-local-direct-target-smoke.sh").read_text(encoding="utf-8")
        target_report = (ROOT / "platform/e2e/release_local_direct_target_smoke_report.py").read_text(encoding="utf-8")
        repeatability_wrapper = (
            ROOT / "platform/e2e/release-local-direct-repeatability-report.sh"
        ).read_text(encoding="utf-8")
        repeatability_report = (
            ROOT / "platform/e2e/release_local_direct_repeatability_report.py"
        ).read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")
        matrix = (ROOT / "docs/engineering/06-product-validation-matrix.md").read_text(encoding="utf-8")
        plan = (ROOT / "docs/engineering/07-development-plan.md").read_text(encoding="utf-8")

        self.assertIn("local-direct-same-chain-smoke.sh", target_wrapper)
        self.assertIn("release_local_direct_target_smoke_report.py", target_wrapper)
        self.assertIn("MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORT", target_wrapper)
        self.assertIn("MA_RELEASE_LOCAL_DIRECT_TARGET_ID", target_wrapper)
        self.assertIn("--target-id", target_wrapper)
        self.assertIn("release-local-direct-target-smoke", target_report)
        self.assertIn("local-direct-same-chain-smoke", target_report)
        self.assertIn("single-target-machine", target_report)
        self.assertIn("not_release_readiness", target_report)
        self.assertIn("release_local_direct_repeatability_report.py", repeatability_wrapper)
        self.assertIn("MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORTS", repeatability_wrapper)
        self.assertIn("MA_RELEASE_LOCAL_DIRECT_EXPECTED_TARGETS", repeatability_wrapper)
        self.assertIn("release-local-direct-repeatability", repeatability_report)
        self.assertIn("incomplete-target-set", repeatability_report)
        self.assertIn("all-target-machines", repeatability_report)
        self.assertIn("not_release_readiness", repeatability_report)
        self.assertIn("release-local-direct-target-smoke.sh", dev_commands)
        self.assertIn("release-local-direct-repeatability-report.sh", dev_commands)
        self.assertIn("release-local-direct-target-smoke.sh", e2e_readme)
        self.assertIn("release-local-direct-repeatability-report.sh", e2e_readme)
        self.assertIn("release-local-direct-repeatability", matrix)
        self.assertIn("release-local-direct-repeatability", plan)

    def test_local_direct_functional_preflight_is_documented_and_guarded(self) -> None:
        wrapper = (ROOT / "platform/e2e/local-direct-functional-preflight.sh").read_text(encoding="utf-8")
        report = (ROOT / "platform/e2e/local_direct_functional_preflight_report.py").read_text(encoding="utf-8")
        dev_commands = (ROOT / "docs/engineering/02-dev-commands.md").read_text(encoding="utf-8")
        e2e_readme = (ROOT / "platform/e2e/README.md").read_text(encoding="utf-8")
        matrix = (ROOT / "docs/engineering/06-product-validation-matrix.md").read_text(encoding="utf-8")
        plan = (ROOT / "docs/engineering/07-development-plan.md").read_text(encoding="utf-8")

        self.assertIn("release-local-direct-target-smoke.sh", wrapper)
        self.assertIn("release-local-direct-repeatability-report.sh", wrapper)
        self.assertIn("release-bundle-create.py", wrapper)
        self.assertIn("target_smoke_exit", wrapper)
        self.assertIn("repeatability_exit", wrapper)
        self.assertIn("failure report", wrapper)
        self.assertIn("--source-app", wrapper)
        self.assertIn("--release-bundle-report", wrapper)
        self.assertIn("local_direct_functional_preflight_report.py", wrapper)
        self.assertIn("MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_ID", wrapper)
        self.assertIn("MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT", wrapper)
        self.assertIn("local-direct-functional-preflight", report)
        self.assertIn("local-machine-only", report)
        self.assertIn("local_direct_app_source", report)
        self.assertIn("source_and_installed_executable_match", report)
        self.assertIn("source_and_installed_unsigned_executable_match", report)
        self.assertIn("not_release_readiness", report)
        self.assertIn("does not run product-validation release or release-preflight", report)
        self.assertIn("source/installed unsigned executable SHA256 match", dev_commands)
        self.assertIn("local-direct-functional-preflight.sh", dev_commands)
        self.assertIn("local-direct-functional-preflight.sh", e2e_readme)
        self.assertIn("installed app unsigned executable content 与当前 source Release app 一致", e2e_readme)
        self.assertIn("local-direct-functional-preflight", matrix)
        self.assertIn("installed app/source app unsigned executable SHA256 一致", matrix)
        self.assertIn("local-direct-functional-preflight", plan)
        self.assertIn("installed app unsigned executable content 匹配当前 source Release app", plan)

    def test_product_validation_current_phase_rejects_missing_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.write_validation_statuses(fixture, "covered", {"PV-MA-010": "missing"})

            result = subprocess.run(
                [sys.executable, str(fixture / "scripts/product-validation-check.py"), "current-phase"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PV-MA-010: current phase cannot leave validation status as missing", result.stderr)

    def test_release_is_fail_closed_outside_project_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            status = fixture / "docs/product-spec/PROJECT-STATUS.md"
            status.write_text(
                re.sub(r"mode: (framework|adoption|project)", "mode: adoption", status.read_text(encoding="utf-8"), count=1),
                encoding="utf-8",
            )
            failures = validate_manifest(fixture, "release")
            self.assertTrue(any("require mode: project" in failure for failure in failures))

    def test_release_requires_dockerfiles_codeowners_and_pinned_compose(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component.pop("dockerfile", None)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            (fixture / ".github/CODEOWNERS").unlink()
            compose_path = fixture / "platform/e2e/docker-compose.smoke.yml"
            compose_path.write_text(
                compose_path.read_text(encoding="utf-8").replace(
                    "meeting-assistant-smoke@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920",
                    "meeting-assistant-smoke:local",
                ),
                encoding="utf-8",
            )
            failures = validate_manifest(fixture, "release")
            self.assertTrue(any("dockerfile is required for release" in failure for failure in failures))
            self.assertTrue(any("CODEOWNERS" in failure for failure in failures))
            self.assertTrue(any("release Compose image must be digest-pinned" in failure for failure in failures))

    def test_project_mode_rejects_unregistered_targets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            status = fixture / "docs/product-spec/PROJECT-STATUS.md"
            status.write_text(
                re.sub(r"mode: (framework|adoption|project)", "mode: project", status.read_text(encoding="utf-8"), count=1),
                encoding="utf-8",
            )
            app = fixture / "frontend/apps/web"
            app.mkdir(parents=True)
            (app / "package.json").write_text('{"scripts": {}}', encoding="utf-8")
            (app / "package-lock.json").write_text("{}", encoding="utf-8")
            failures = validate_manifest(fixture, "development")
            self.assertTrue(any("frontend/backend/platform component targets" in failure for failure in failures))

    def test_project_mode_rejects_unregistered_platform_component(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            rogue = fixture / "platform/rogue-adapter"
            rogue.mkdir(parents=True)
            (rogue / "component.json").write_text(
                json.dumps(
                    {
                        "id": "rogue-adapter",
                        "kind": "project-component",
                        "scope": "platform",
                        "business_behavior": "none",
                        "allowed_before_project_mode": False,
                    }
                ),
                encoding="utf-8",
            )

            failures = validate_manifest(fixture, "development")
            self.assertTrue(any("frontend/backend/platform component targets" in failure for failure in failures))
            self.assertTrue(any("platform/rogue-adapter" in failure for failure in failures))

    def test_spec_sync_rejects_platform_source_without_validation_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            source = fixture / "platform/processing-cli/src/meeting_assistant_cli/dependency_check.py"
            source.write_text(source.read_text(encoding="utf-8") + "\n# platform product behavior drift\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/spec-sync-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            combined = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Product surface changes require docs/engineering/06-product-validation-matrix.md", combined)
            self.assertIn("platform/processing-cli/src/meeting_assistant_cli/dependency_check.py", combined)

    def test_agent_workflow_rejects_platform_implementation_without_test_change(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            source = fixture / "platform/processing-cli/src/meeting_assistant_cli/dependency_check.py"
            source.write_text(source.read_text(encoding="utf-8") + "\n# implementation changed without test\n", encoding="utf-8")
            matrix = fixture / "docs/engineering/06-product-validation-matrix.md"
            matrix.write_text(matrix.read_text(encoding="utf-8") + "\n<!-- platform validation reviewed -->\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/agent-workflow-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            combined = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Implementation changes require corresponding backend, frontend, platform, E2E, or test script changes.", combined)

    def test_agent_workflow_accepts_platform_implementation_with_test_and_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            source = fixture / "platform/processing-cli/src/meeting_assistant_cli/dependency_check.py"
            source.write_text(source.read_text(encoding="utf-8") + "\n# implementation changed with test\n", encoding="utf-8")
            test_file = fixture / "platform/processing-cli/tests/test_dependency_check.py"
            test_file.write_text(test_file.read_text(encoding="utf-8") + "\n# platform test updated\n", encoding="utf-8")
            matrix = fixture / "docs/engineering/06-product-validation-matrix.md"
            matrix.write_text(matrix.read_text(encoding="utf-8") + "\n<!-- platform validation reviewed -->\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/agent-workflow-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_review_report_recommends_platform_validation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            source = fixture / "platform/processing-cli/src/meeting_assistant_cli/dependency_check.py"
            source.write_text(source.read_text(encoding="utf-8") + "\n# review report platform surface\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("platform/processing-cli/src/meeting_assistant_cli/dependency_check.py", result.stdout)
            self.assertIn("./scripts/test-e2e-full-stack.sh", result.stdout)
            self.assertIn("./scripts/architecture-check.sh", result.stdout)
            self.assertIn("./scripts/security-check.sh", result.stdout)

    def test_prepare_smoke_image_accepts_no_pull_run_when_inspect_misses_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = Path(directory) / "bin"
            fake_bin.mkdir()
            docker_log = Path(directory) / "docker.log"
            fake_docker = fake_bin / "docker"
            fake_docker.write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "printf '%s\\n' \"$*\" >> \"${FAKE_DOCKER_LOG}\"",
                        "case \"${1:-}\" in",
                        "  info)",
                        "    exit 0",
                        "    ;;",
                        "  image)",
                        "    if [ \"${2:-}\" = inspect ]; then",
                        "      exit 1",
                        "    fi",
                        "    if [ \"${2:-}\" = tag ]; then",
                        "      exit 0",
                        "    fi",
                        "    ;;",
                        "  run)",
                        "    if [ \"${2:-}\" = --rm ] && [ \"${3:-}\" = --pull=never ] && [ \"${4:-}\" = --network ] && [ \"${5:-}\" = none ] && [ \"${6:-}\" = fixture-smoke:local ]; then",
                        "      exit 0",
                        "    fi",
                        "    exit 1",
                        "    ;;",
                        "esac",
                        "exit 1",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            fake_docker.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "FAKE_DOCKER_LOG": str(docker_log),
                    "MEETING_ASSISTANT_SMOKE_IMAGE": "fixture-smoke:local",
                    "MEETING_ASSISTANT_SMOKE_IMAGE_PROBE_ATTEMPTS": "1",
                    "PATH": f"{fake_bin}{os.pathsep}{env['PATH']}",
                }
            )

            result = subprocess.run(
                [str(ROOT / "platform/e2e/prepare-smoke-image.sh")],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            combined = result.stderr + result.stdout
            self.assertIn("target image inspect did not find image; no-pull run probe succeeded: fixture-smoke:local", combined)
            self.assertIn("local smoke image available and runnable: fixture-smoke:local", combined)
            docker_calls = docker_log.read_text(encoding="utf-8")
            self.assertIn("image inspect fixture-smoke:local", docker_calls)
            self.assertIn("run --rm --pull=never --network none fixture-smoke:local sh -c sleep 0", docker_calls)
            self.assertNotIn("image tag", docker_calls)

    def test_review_report_require_evidence_rejects_stale_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            evidence_dir = fixture / ".harness/evidence/check"
            evidence_dir.mkdir(parents=True)
            for index in range(200):
                (evidence_dir / f"stale-{index}.log").write_text("stale evidence\n", encoding="utf-8")
                (evidence_dir / f"stale-{index}.meta").write_text(
                    "\n".join(
                        [
                            f"step=stale-{index}",
                            "exit_code=0",
                            "worktree_fingerprint=stale",
                            "command=./scripts/check.sh",
                            f"log=.harness/evidence/check/stale-{index}.log",
                            "",
                        ]
                    ),
                    encoding="utf-8",
                )

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("validation evidence is stale", result.stderr + result.stdout)

    def test_review_report_require_evidence_rejects_failed_command_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            evidence_dir = fixture / ".harness/evidence/check"
            evidence_dir.mkdir(parents=True)
            fingerprint = subprocess.check_output(
                [sys.executable, str(fixture / "scripts/worktree-fingerprint.py")],
                cwd=fixture,
                text=True,
            ).strip()
            (evidence_dir / "failed.log").write_text("failed evidence\n", encoding="utf-8")
            (evidence_dir / "failed.meta").write_text(
                "\n".join(
                    [
                        "step=failed",
                        "exit_code=1",
                        f"worktree_fingerprint={fingerprint}",
                        "command=./scripts/check.sh",
                        "log=.harness/evidence/check/failed.log",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("validation evidence contains failed commands", result.stderr + result.stdout)

    def test_review_report_require_evidence_rejects_partial_check_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            evidence_dir = fixture / ".harness/evidence/check"
            evidence_dir.mkdir(parents=True)
            fingerprint = subprocess.check_output(
                [sys.executable, str(fixture / "scripts/worktree-fingerprint.py")],
                cwd=fixture,
                text=True,
            ).strip()
            (evidence_dir / "lint.log").write_text("lint passed\n", encoding="utf-8")
            (evidence_dir / "lint.meta").write_text(
                "\n".join(
                    [
                        "step=lint",
                        "exit_code=0",
                        f"worktree_fingerprint={fingerprint}",
                        "command=./scripts/lint.sh",
                        "log=.harness/evidence/check/lint.log",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required validation evidence step docs-check", result.stderr + result.stdout)

    def test_review_report_require_release_evidence_rejects_check_scope_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            fingerprint = self.worktree_fingerprint(fixture)
            for step in (
                "production-readiness",
                "docs",
                "check",
                "mocked-e2e",
                "full-stack-e2e",
                "supply-chain",
            ):
                self.write_evidence_step(fixture, "check", step, fingerprint)

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-release-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no recorded release validation evidence", result.stderr + result.stdout)

    def test_review_report_require_release_evidence_rejects_readiness_only_release_scope(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            fingerprint = self.worktree_fingerprint(fixture)
            self.write_evidence_step(
                fixture,
                "release",
                "production-readiness",
                fingerprint,
                command="./scripts/production-readiness-check.sh",
            )

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-release-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required release validation evidence step docs", result.stderr + result.stdout)

    def test_review_report_require_evidence_rejects_bundle_without_harness_self_test(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            evidence_dir = fixture / ".harness/evidence/check"
            evidence_dir.mkdir(parents=True)
            fingerprint = subprocess.check_output(
                [sys.executable, str(fixture / "scripts/worktree-fingerprint.py")],
                cwd=fixture,
                text=True,
            ).strip()
            for step in (
                "docs-check",
                "adoption",
                "manifest",
                "compose",
                "workflow",
                "prod-config",
                "architecture",
                "security",
                "supply-chain",
                "migration",
                "lint",
                "test",
                "build",
            ):
                (evidence_dir / f"{step}.log").write_text(f"{step} passed\n", encoding="utf-8")
                (evidence_dir / f"{step}.meta").write_text(
                    "\n".join(
                        [
                            f"step={step}",
                            "exit_code=0",
                            f"worktree_fingerprint={fingerprint}",
                            f"command=./scripts/{step}.sh",
                            f"log=.harness/evidence/check/{step}.log",
                            "",
                        ]
                    ),
                    encoding="utf-8",
                )

            result = subprocess.run(
                [str(fixture / "scripts/review-report.sh"), "--require-evidence"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required validation evidence step harness-self-test", result.stderr + result.stdout)

    def test_supply_chain_current_runs_registered_sbom_gates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current.log"
            command = self.supply_chain_report_command(marker)
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(marker.read_text(encoding="utf-8"), "sbom\nsbom\n")
            self.assertIn("supply-chain evidence reports passed.", result.stdout)
            self.assertIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_current_fails_when_production_component_supply_chain_report_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-no-report.log"
            command = self.supply_chain_report_command(marker, write_report=False)
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(encoding="utf-8"), "sbom\nsbom\n")
            self.assertIn("missing supply-chain report for production component", output)
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_current_fails_when_production_component_supply_chain_report_has_unsafe_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            command = self.supply_chain_report_command(
                overrides={
                    "sca_dependency_review": False,
                    "license_review": False,
                    "packages_runtime_or_model": True,
                    "auto_downloads": True,
                    "provenance_scope": "release",
                    "release_provenance_attestation": "claimed",
                    "findings": ["unreviewed supply-chain issue"],
                }
            )
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must set sca_dependency_review=True", output)
            self.assertIn("must set license_review=True", output)
            self.assertIn("must set packages_runtime_or_model=False", output)
            self.assertIn("must set auto_downloads=False", output)
            self.assertIn("must set provenance_scope='validation-only'", output)
            self.assertIn("must set release_provenance_attestation='not-produced'", output)
            self.assertIn("must report zero findings", output)
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_local_direct_release_fails_without_bundle_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release supply-chain local-direct bundle evidence failed", output)
            self.assertIn("release bundle report is required", output)
            self.assertNotIn("release provenance report is required", output)
            self.assertNotIn("release signature report is required", output)
            self.assertNotIn("release sidecar report is required", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_developer_id_release_fails_without_release_bundle_provenance_signature_and_sidecar_reports(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_DISTRIBUTION_MODE"] = "developer-id"

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release supply-chain bundle/provenance/signing/sidecar evidence failed", output)
            self.assertIn("release bundle report is required", output)
            self.assertIn("release provenance report is required", output)
            self.assertIn("release signature report is required", output)
            self.assertIn("release sidecar report is required", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_accepts_provenance_signature_and_sidecar_reports(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release supply-chain bundle/provenance/signing/sidecar evidence passed", result.stdout)
            self.assertIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_local_direct_release_accepts_bundle_without_distribution_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            reports_dir = fixture / ".harness/release-inputs/bundle"
            reports_dir.mkdir(parents=True)
            bundle_path = reports_dir / "MeetingAssistantNative-LocalDirect.zip"
            app_root = reports_dir / "fixture-app" / "MeetingAssistantNative.app"
            contents = app_root / "Contents"
            macos = contents / "MacOS"
            macos.mkdir(parents=True)
            (contents / "Info.plist").write_text(
                (
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                    "<plist version=\"1.0\"><dict>"
                    "<key>CFBundleExecutable</key><string>MeetingAssistantNative</string>"
                    "<key>CFBundleIdentifier</key><string>local.meeting-assistant.native</string>"
                    "<key>CFBundleName</key><string>MeetingAssistantNative</string>"
                    "<key>CFBundlePackageType</key><string>APPL</string>"
                    "</dict></plist>\n"
                ),
                encoding="utf-8",
            )
            executable = macos / "MeetingAssistantNative"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            subprocess.run(
                ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app_root)],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", str(app_root), str(bundle_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            digest = "sha256:" + hashlib.sha256(bundle_path.read_bytes()).hexdigest()
            report_path = reports_dir / "release-bundle-report.json"
            report_path.write_text(
                json.dumps(
                    {
                        "report_schema": 1,
                        "release_gate": "release-bundle",
                        "subject_commit": head,
                        "builder": "local-release-rehearsal",
                        "source_repository": "example/meeting_assistant",
                        "bundle": {
                            "name": bundle_path.name,
                            "path": str(bundle_path.relative_to(fixture)),
                            "digest": digest,
                            "artifact_type": "macos-app-archive",
                            "archive_format": "zip",
                            "app_bundle": "MeetingAssistantNative.app",
                            "build_configuration": "Release",
                            "code_signed": True,
                            "distribution_mode": "local-direct",
                            "install_method": "direct-local-app",
                            "signing_identity": "ad-hoc-local",
                            "notarized": False,
                            "notarization_ticket": "not-applicable",
                            "stapled": False,
                            "packages_runtime_or_model": False,
                            "auto_downloads": False,
                            "contains_meeting_data": False,
                        },
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release supply-chain local-direct bundle evidence passed", result.stdout)
            self.assertIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_provenance_or_signature_for_different_bundle_digest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            bundle_digest = "sha256:" + ("a" * 64)
            other_digest = "sha256:" + ("b" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                bundle_digest,
                provenance_digest=other_digest,
                signature_digest=other_digest,
            )
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release provenance report must include release bundle artifact digest", output)
            self.assertIn("release signature report must include release bundle artifact digest", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_missing_slsa_attestation_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
            provenance.pop("attestation")
            provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release provenance attestation must be an object", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_signature_without_sigstore_bundle_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            signature = json.loads(signature_path.read_text(encoding="utf-8"))
            signature["signed_artifacts"][0].pop("signature_bundle")
            signature_path.write_text(json.dumps(signature), encoding="utf-8")
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release signature artifact signature_bundle must be an object", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_sidecar_without_target_smoke_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            sidecar["target_machines"][0].pop("smoke_report")
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release sidecar target_machine #0 smoke_report must be an object", output)
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_sidecar_smoke_report_digest_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            smoke_report_path = Path(sidecar["target_machines"][0]["smoke_report"]["path"])
            smoke_report = json.loads(smoke_report_path.read_text(encoding="utf-8"))
            smoke_report["artifacts"]["model"]["digest"] = "sha256:" + ("c" * 64)
            smoke_report_path.write_text(json.dumps(smoke_report), encoding="utf-8")
            sidecar["target_machines"][0]["smoke_report"]["digest"] = (
                "sha256:" + hashlib.sha256(smoke_report_path.read_bytes()).hexdigest()
            )
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "release sidecar target_machine #0 smoke_report model digest must match target machine model digest",
                output,
            )
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_supply_chain_release_rejects_sidecar_smoke_report_failed_smoke(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            digest = "sha256:" + ("a" * 64)
            command = self.supply_chain_report_command()
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports_dir = Path(directory) / "release-reports"
            bundle_path, provenance_path, signature_path, sidecar_path = self.write_release_supply_chain_reports(
                reports_dir,
                manifest,
                head,
                digest,
            )
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            smoke_report_path = Path(sidecar["target_machines"][0]["smoke_report"]["path"])
            smoke_report = json.loads(smoke_report_path.read_text(encoding="utf-8"))
            smoke_report["smoke"]["no_auto_downloads_observed"] = False
            smoke_report_path.write_text(json.dumps(smoke_report), encoding="utf-8")
            sidecar["target_machines"][0]["smoke_report"]["digest"] = (
                "sha256:" + hashlib.sha256(smoke_report_path.read_bytes()).hexdigest()
            )
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            env = os.environ.copy()
            env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_path)
            env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_path)
            env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_path)
            env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_path)

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "release"],
                cwd=fixture,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "release sidecar target_machine #0 smoke_report smoke must set no_auto_downloads_observed=True",
                output,
            )
            self.assertNotIn("supply-chain-check passed: phase=release", result.stdout)

    def test_release_bundle_check_fails_without_release_bundle_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)

            result = subprocess.run(
                [str(fixture / "scripts/release-bundle-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release bundle evidence failed", output)
            self.assertIn("release bundle report is required", output)
            self.assertNotIn("release-bundle-check passed", result.stdout)

    def test_release_bundle_check_accepts_local_direct_ad_hoc_zip_archive_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            reports_dir = fixture / ".harness/release-inputs/bundle"
            reports_dir.mkdir(parents=True)
            bundle_path = reports_dir / "MeetingAssistantNative-LocalDirect.zip"
            app_root = reports_dir / "fixture-app" / "MeetingAssistantNative.app"
            contents = app_root / "Contents"
            macos = contents / "MacOS"
            macos.mkdir(parents=True)
            (contents / "Info.plist").write_text(
                (
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                    "<plist version=\"1.0\"><dict>"
                    "<key>CFBundleExecutable</key><string>MeetingAssistantNative</string>"
                    "<key>CFBundleIdentifier</key><string>local.meeting-assistant.native</string>"
                    "<key>CFBundleName</key><string>MeetingAssistantNative</string>"
                    "<key>CFBundlePackageType</key><string>APPL</string>"
                    "</dict></plist>\n"
                ),
                encoding="utf-8",
            )
            executable = macos / "MeetingAssistantNative"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            subprocess.run(
                ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app_root)],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", str(app_root), str(bundle_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            digest = "sha256:" + hashlib.sha256(bundle_path.read_bytes()).hexdigest()
            report_path = reports_dir / "release-bundle-report.json"
            report_path.write_text(
                json.dumps(
                    {
                        "report_schema": 1,
                        "release_gate": "release-bundle",
                        "subject_commit": head,
                        "builder": "local-release-rehearsal",
                        "source_repository": "example/meeting_assistant",
                        "bundle": {
                            "name": bundle_path.name,
                            "path": str(bundle_path.relative_to(fixture)),
                            "digest": digest,
                            "artifact_type": "macos-app-archive",
                            "archive_format": "zip",
                            "app_bundle": "MeetingAssistantNative.app",
                            "build_configuration": "Release",
                            "code_signed": True,
                            "distribution_mode": "local-direct",
                            "install_method": "direct-local-app",
                            "signing_identity": "ad-hoc-local",
                            "notarized": False,
                            "notarization_ticket": "not-applicable",
                            "stapled": False,
                            "packages_runtime_or_model": False,
                            "auto_downloads": False,
                            "contains_meeting_data": False,
                        },
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/release-bundle-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release bundle evidence passed", result.stdout)
            self.assertIn("release-bundle-check passed", result.stdout)

    def test_release_bundle_check_rejects_unsigned_unstapled_zip_archive_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            self.init_git_baseline(fixture)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture, text=True).strip()
            reports_dir = fixture / ".harness/release-inputs/bundle"
            reports_dir.mkdir(parents=True)
            bundle_path = reports_dir / "MeetingAssistantNative.zip"
            app_root = reports_dir / "fixture-app" / "MeetingAssistantNative.app"
            contents = app_root / "Contents"
            macos = contents / "MacOS"
            macos.mkdir(parents=True)
            (contents / "Info.plist").write_text(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict /></plist>\n",
                encoding="utf-8",
            )
            executable = macos / "MeetingAssistantNative"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            with zipfile.ZipFile(bundle_path, "w") as archive:
                for path in sorted(app_root.rglob("*")):
                    archive.write(path, path.relative_to(app_root.parent))
            digest = "sha256:" + hashlib.sha256(bundle_path.read_bytes()).hexdigest()
            report_path = reports_dir / "release-bundle-report.json"
            report_path.write_text(
                json.dumps(
                    {
                        "report_schema": 1,
                        "release_gate": "release-bundle",
                        "subject_commit": head,
                        "builder": "github-actions-oidc",
                        "source_repository": "example/meeting_assistant",
                        "bundle": {
                            "name": bundle_path.name,
                            "path": str(bundle_path.relative_to(fixture)),
                            "digest": digest,
                            "artifact_type": "macos-app-archive",
                            "archive_format": "zip",
                            "app_bundle": "MeetingAssistantNative.app",
                            "build_configuration": "Release",
                            "code_signed": True,
                            "distribution_mode": "developer-id",
                            "install_method": "developer-id-zip",
                            "signing_identity": "Developer ID Application",
                            "notarized": True,
                            "notarization_ticket": "ticket-id",
                            "stapled": True,
                            "packages_runtime_or_model": False,
                            "auto_downloads": False,
                            "contains_meeting_data": False,
                        },
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(fixture / "scripts/release-bundle-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("codesign", output)
            self.assertNotIn("release-bundle-check passed", result.stdout)

    def test_security_check_runs_registered_security_gates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current.log"
            command = self.security_report_command(marker)
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["security"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(marker.read_text(encoding="utf-8"), "security\nsecurity\n")
            self.assertIn("security-check passed.", result.stdout)

    def test_security_check_fails_when_production_component_security_report_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-no-report.log"
            command = self.security_report_command(marker, write_report=False)
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["security"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(encoding="utf-8"), "security\nsecurity\n")
            self.assertIn("missing security report for production component", output)
            self.assertNotIn("security-check passed.", result.stdout)

    def test_security_check_fails_when_production_component_security_report_has_unsafe_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            command = self.security_report_command(
                overrides={
                    "sast_static_analysis": False,
                    "sca_dependency_review": False,
                    "external_network_access": True,
                    "packages_runtime_or_model": True,
                    "findings": ["unreviewed issue"],
                }
            )
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["security"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must set sast_static_analysis=True", output)
            self.assertIn("must set sca_dependency_review=True", output)
            self.assertIn("must set external_network_access=False", output)
            self.assertIn("must set packages_runtime_or_model=False", output)
            self.assertIn("must report zero findings", output)
            self.assertNotIn("security-check passed.", result.stdout)

    def test_supply_chain_current_fails_when_registered_sbom_gate_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-failure.log"
            command = [
                sys.executable,
                "-c",
                (
                    "import sys; "
                    "from pathlib import Path; "
                    f"Path({str(marker)!r}).open('a').write('failed\\n'); "
                    "sys.stderr.write('sbom forced failure\\n'); "
                    "sys.exit(17)"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(encoding="utf-8"), "failed\n")
            self.assertIn("sbom forced failure", output)
            self.assertIn("harness runtime failed", output)
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_security_check_fails_when_registered_security_gate_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-failure.log"
            command = [
                sys.executable,
                "-c",
                (
                    "import sys; "
                    "from pathlib import Path; "
                    f"Path({str(marker)!r}).open('a').write('failed\\n'); "
                    "sys.stderr.write('security forced failure\\n'); "
                    "sys.exit(19)"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["security"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(encoding="utf-8"), "failed\n")
            self.assertIn("security forced failure", output)
            self.assertIn("harness runtime failed", output)
            self.assertNotIn("security-check passed.", result.stdout)

    def test_supply_chain_current_fails_when_production_component_lacks_sbom_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-missing.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('sbom\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            production_components[0]["commands"].pop("sbom", None)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.sbom must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_current_fails_when_production_component_has_non_argv_sbom_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-non-argv.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('sbom\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            production_components[0]["commands"]["sbom"] = "./scripts/sbom.sh"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.sbom must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_current_fails_when_production_component_uses_shell_sbom_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-shell.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('sbom\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            production_components[0]["commands"]["sbom"] = ["sh", "-c", "printf shell > \"$1\"", "sh", str(marker)]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.sbom must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_supply_chain_current_fails_when_production_component_uses_noop_sbom_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "sbom-current-noop.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('sbom\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["sbom"] = command
            production_components[0]["commands"]["sbom"] = ["true"]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/supply-chain-check.sh"), "current"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.sbom must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("supply-chain-check passed: phase=current", result.stdout)

    def test_security_check_fails_when_production_component_lacks_security_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-missing.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('security\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["security"] = command
            production_components[0]["commands"].pop("security", None)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.security must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("security-check passed.", result.stdout)

    def test_security_check_fails_when_production_component_uses_noop_security_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-noop.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('security\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["security"] = command
            production_components[0]["commands"]["security"] = ["true"]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.security must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("security-check passed.", result.stdout)

    def test_security_check_fails_when_production_component_uses_shell_security_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-shell.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('security\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["security"] = command
            production_components[0]["commands"]["security"] = [
                "sh",
                "-c",
                "printf shell > \"$1\"",
                "sh",
                str(marker),
            ]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.security must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("security-check passed.", result.stdout)

    def test_security_check_fails_when_production_component_has_non_argv_security_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current-non-argv.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('security\\n')",
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            production_components = [
                component for component in manifest["components"] if component.get("production") is True
            ]
            self.assertGreaterEqual(len(production_components), 1)
            for component in manifest["components"]:
                component["commands"]["security"] = command
            production_components[0]["commands"]["security"] = "./scripts/security.sh"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/security-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness manifest validation failed for phase=current", output)
            self.assertIn("commands.security must be a non-empty argv array", output)
            self.assertFalse(marker.exists())
            self.assertNotIn("security-check passed.", result.stdout)

    def test_build_gate_requires_production_component_build_reports(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("build validation image evidence reports passed", result.stdout)

    def test_build_gate_fails_when_production_component_build_report_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [sys.executable, "-c", "from pathlib import Path; Path('build').mkdir(exist_ok=True)"]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing build report for production component", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_build_report_is_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "from pathlib import Path; "
                    "Path('build').mkdir(exist_ok=True); "
                    "Path('build/build-report.json').write_text('{not-json', encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid build report JSON for production component", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_build_report_is_not_json_object(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "from pathlib import Path; "
                    "Path('build').mkdir(exist_ok=True); "
                    "Path('build/build-report.json').write_text('[]', encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be a JSON object", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_build_report_has_unsafe_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': True, "
                    "'auto_downloads': True, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must set packages_runtime_or_model=False", output)
            self.assertIn("must set auto_downloads=False", output)

    def test_build_gate_fails_when_production_component_build_report_lacks_container_hardening(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': False, "
                    "'non_root_user': False, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must set digest_pinned_base=True", output)
            self.assertIn("must set non_root_user=True", output)

    def test_build_gate_fails_when_production_component_build_report_misstates_identity_or_gate_image(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': 'unexpected-' + component['id'], "
                    "'release_gate_image': 'production-runtime', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must set component=", output)
            self.assertIn("must set release_gate_image='validation-only'", output)

    def test_build_gate_fails_when_production_component_build_report_packages_macos_app(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'packages_macos_app': True, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must not package a macOS app", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_build_report_missing_sbom(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must reference a component SBOM", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_build_report_misstates_sbom_name(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'sbom': 'unexpected-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must reference a generated component SBOM name", result.stderr + result.stdout)

    def test_build_gate_fails_when_production_component_sbom_is_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            for build_dir in fixture.glob("platform/*/build"):
                shutil.rmtree(build_dir)
            command = [
                sys.executable,
                "-c",
                (
                    "import json; "
                    "from pathlib import Path; "
                    "component = json.loads(Path('component.json').read_text(encoding='utf-8')); "
                    "Path('build').mkdir(exist_ok=True); "
                    "report = {"
                    "'component': component['id'], "
                    "'release_gate_image': 'validation-only', "
                    "'digest_pinned_base': True, "
                    "'non_root_user': True, "
                    "'packages_runtime_or_model': False, "
                    "'auto_downloads': False, "
                    "'sbom': 'meeting-assistant-' + component['id']"
                    "}; "
                    "Path('build/build-report.json').write_text(json.dumps(report), encoding='utf-8'); "
                    "next(Path('sbom').glob('*.cdx.json')).write_text('{not-json', encoding='utf-8')"
                ),
            ]
            manifest_path = fixture / "harness/project-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for component in manifest["components"]:
                component["commands"]["build"] = command
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/build.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )

            output = result.stderr + result.stdout
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid component SBOM JSON for production component", output)
            self.assertIn("must reference a generated component SBOM name", output)

    def test_insecure_agent_network_policy_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            policy_path = fixture / "harness/agent-policy.json"
            policy = json.loads(policy_path.read_text(encoding="utf-8"))
            policy["profiles"]["implementation"]["network"] = "allow-all"
            policy_path.write_text(json.dumps(policy), encoding="utf-8")
            failures = validate_agent_policy(fixture)
            self.assertIn("implementation network must be allowlist", failures)

    def test_start_project_initializes_adoption_and_blocks_empty_activation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            status = fixture / "docs/product-spec/PROJECT-STATUS.md"
            status.write_text(
                re.sub(r"mode: (framework|adoption|project)", "mode: framework", status.read_text(encoding="utf-8"), count=1),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    str(fixture / "scripts/start-project.sh"),
                    "--name",
                    "Acme Workflow",
                    "--owner",
                    "Platform Team",
                ],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("mode: adoption", (fixture / "docs/product-spec/PROJECT-STATUS.md").read_text(encoding="utf-8"))
            state = json.loads((fixture / "harness/adoption-state.json").read_text(encoding="utf-8"))
            self.assertEqual("Acme Workflow", state["project"]["name"])
            manifest = json.loads((fixture / "harness/project-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual("Platform Team", manifest["project"]["owner"])
            manifest["components"] = []
            manifest["full_stack_e2e"] = {"compose_files": [], "services": [], "seed_command": [], "test_command": [], "cleanup": True}
            (fixture / "harness/project-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            (fixture / "docs/adoption/INITIAL-REQUEST.md").write_text(
                "# Initial Project Request\n\nSTARTER_TEMPLATE\n\nReplace this section before activation.\n",
                encoding="utf-8",
            )

            activation = subprocess.run(
                [str(fixture / "scripts/adoption-check.sh"), "--activation"],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(activation.returncode, 0)
            combined = activation.stderr + activation.stdout
            self.assertIn("INITIAL-REQUEST.md still contains starter template markers", combined)
            self.assertIn("project activation requires at least one registered component skeleton", combined)
            self.assertIn("project activation requires full_stack_e2e.compose_files", combined)

    def test_activate_project_requires_explicit_arguments_and_does_not_switch_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            status = fixture / "docs/product-spec/PROJECT-STATUS.md"
            status.write_text(
                re.sub(r"mode: (framework|adoption|project)", "mode: framework", status.read_text(encoding="utf-8"), count=1),
                encoding="utf-8",
            )
            subprocess.run(
                [
                    str(fixture / "scripts/start-project.sh"),
                    "--name",
                    "Acme Workflow",
                    "--owner",
                    "Platform Team",
                ],
                cwd=fixture,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(fixture / "scripts/activate-project.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("mode: adoption", (fixture / "docs/product-spec/PROJECT-STATUS.md").read_text(encoding="utf-8"))

    def test_activation_lifecycle_diff_passes_agent_workflow(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            subprocess.run(["git", "init", "-b", "main"], cwd=fixture, check=True, capture_output=True, text=True)
            subprocess.run(["git", "config", "user.name", "Harness Test"], cwd=fixture, check=True)
            subprocess.run(["git", "config", "user.email", "harness@example.test"], cwd=fixture, check=True)
            subprocess.run(["git", "add", "."], cwd=fixture, check=True, capture_output=True, text=True)
            subprocess.run(["git", "commit", "-m", "baseline"], cwd=fixture, check=True, capture_output=True, text=True)

            status = fixture / "docs/product-spec/PROJECT-STATUS.md"
            status.write_text(
                re.sub(r"mode: (framework|adoption|project)", "mode: project", status.read_text(encoding="utf-8"), count=1),
                encoding="utf-8",
            )
            state_path = fixture / "harness/adoption-state.json"
            state = json.loads(state_path.read_text(encoding="utf-8"))
            state["adoption"]["subphase"] = "ready-for-activation"
            state["adoption"]["confirmation"] = {
                "product_spec_reviewed": True,
                "blocking_open_decisions_closed": True,
                "approved_for_project_activation": True,
                "confirmed_by": "Harness Test",
                "confirmed_at": "2026-06-26T00:00:00+00:00",
                "confirmation_text": "Harness test reviewed specs and approved project activation.",
            }
            state["adoption"]["blockers"] = []
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            result = subprocess.run(
                [str(fixture / "scripts/agent-workflow-check.sh")],
                cwd=fixture,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_full_stack_runner_executes_config_up_seed_test_and_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "repo"
            (fixture / "docs/product-spec").mkdir(parents=True)
            (fixture / "harness").mkdir()
            service = fixture / "backend/services/api"
            service.mkdir(parents=True)
            architecture_test = service / "src/test/ArchitectureTest.java"
            architecture_test.parent.mkdir(parents=True)
            architecture_test.write_text("class ArchitectureTest {}", encoding="utf-8")
            (service / "pom.xml").write_text("<project/>", encoding="utf-8")
            mvnw = service / "mvnw"
            mvnw.write_text("#!/usr/bin/env sh\nexit 0\n", encoding="utf-8")
            mvnw.chmod(0o755)
            (fixture / "docs/product-spec/PROJECT-STATUS.md").write_text("mode: project\n", encoding="utf-8")
            shutil.copy(ROOT / "harness/agent-policy.json", fixture / "harness/agent-policy.json")
            marker = fixture / "runner.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('component-command\\n')",
            ]
            manifest = {
                "schema_version": 1,
                "project": {"name": "example", "owner": "team"},
                "components": [
                    {
                        "id": "api",
                        "type": "backend",
                        "path": "backend/services/api",
                        "production": True,
                        "requires_migrations": False,
                        "architecture_test": "backend/services/api/src/test/ArchitectureTest.java",
                        "dockerfile": "backend/services/api/Dockerfile",
                        "commands": {
                            "lint": command,
                            "test": command,
                            "build": command,
                            "architecture": command,
                            "security": command,
                            "sbom": command,
                        },
                    }
                ],
                "full_stack_e2e": {
                    "compose_files": ["docker-compose.yml"],
                    "services": ["api"],
                    "pre_start_command": [
                        sys.executable,
                        "-c",
                        f"from pathlib import Path; Path({str(marker)!r}).open('a').write('prestart\\n')",
                    ],
                    "seed_command": [
                        sys.executable,
                        "-c",
                        f"from pathlib import Path; Path({str(marker)!r}).open('a').write('seed\\n')",
                    ],
                    "test_command": [
                        sys.executable,
                        "-c",
                        f"from pathlib import Path; Path({str(marker)!r}).open('a').write('test\\n')",
                    ],
                    "cleanup": True,
                },
                "release_policy": {},
                "production_readiness": {},
                "supply_chain": {},
            }
            (fixture / "harness/project-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            (fixture / "docker-compose.yml").write_text(
                "services:\n  api:\n    image: example/api:test\n",
                encoding="utf-8",
            )

            fake_bin = fixture / "fake-bin"
            fake_bin.mkdir()
            fake_docker = fake_bin / "docker"
            fake_docker.write_text(
                "#!/usr/bin/env sh\n"
                f"printf 'docker %s\\n' \"$*\" >> {str(marker)!r}\n",
                encoding="utf-8",
            )
            fake_docker.chmod(0o755)
            env = os.environ.copy()
            env["HARNESS_ROOT"] = str(fixture)
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/harness-runtime.py"), "full-stack-e2e"],
                check=True,
                env=env,
                cwd=fixture,
                capture_output=True,
                text=True,
            )
            output = marker.read_text(encoding="utf-8")
            self.assertIn("prestart", output)
            self.assertIn("docker compose -f docker-compose.yml config --quiet", output)
            self.assertIn("docker compose -f docker-compose.yml up --detach --wait api", output)
            self.assertIn("seed", output)
            self.assertIn("test", output)
            self.assertIn("docker compose -f docker-compose.yml down --volumes --remove-orphans", output)


if __name__ == "__main__":
    unittest.main()
