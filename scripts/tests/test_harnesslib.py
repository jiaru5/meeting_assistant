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

    def test_release_is_fail_closed_outside_project_mode(self) -> None:
        failures = validate_manifest(ROOT, "release")
        self.assertTrue(any("require mode: project" in failure for failure in failures))
        self.assertTrue(any("dockerfile is required for release" in failure for failure in failures))
        self.assertTrue(any("CODEOWNERS" in failure for failure in failures))

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
            self.assertTrue(any("frontend/backend targets" in failure for failure in failures))

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
            self.assertIn("docker compose -f docker-compose.yml config --quiet", output)
            self.assertIn("docker compose -f docker-compose.yml up --detach --wait api", output)
            self.assertIn("seed", output)
            self.assertIn("test", output)
            self.assertIn("docker compose -f docker-compose.yml down --volumes --remove-orphans", output)


if __name__ == "__main__":
    unittest.main()
