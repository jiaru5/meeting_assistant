from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import importlib.util
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


class HarnessValidationTests(unittest.TestCase):
    def copy_repo_fixture(self, directory: str) -> Path:
        fixture = Path(directory) / "repo"
        shutil.copytree(
            ROOT,
            fixture,
            ignore=shutil.ignore_patterns(
                ".git",
                ".harness",
                "__pycache__",
                "example-smart_team-harness_engineering",
            ),
        )
        return fixture

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

    def test_release_preflight_fails_closed_when_pv_rows_are_partial(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
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
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('sbom\\n')",
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

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(marker.read_text(encoding="utf-8"), "sbom\nsbom\n")
            self.assertIn("supply-chain-check passed: phase=current", result.stdout)

    def test_security_check_runs_registered_security_gates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self.copy_repo_fixture(directory)
            marker = fixture / "security-current.log"
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).open('a').write('security\\n')",
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

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(marker.read_text(encoding="utf-8"), "security\nsecurity\n")
            self.assertIn("security-check passed.", result.stdout)

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
