#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent

STATE_PATH = ROOT / "harness/adoption-state.json"
MANIFEST_PATH = ROOT / "harness/project-manifest.json"
STATUS_PATH = ROOT / "docs/product-spec/PROJECT-STATUS.md"
INITIAL_REQUEST = ROOT / "docs/adoption/INITIAL-REQUEST.md"
DISCOVERY_LEDGER = ROOT / "docs/adoption/DISCOVERY-LEDGER.md"
SPEC_READINESS = ROOT / "docs/adoption/SPEC-READINESS.md"

ADOPTION_DOCS = {
    INITIAL_REQUEST: ROOT / "templates/project-intake.md",
    DISCOVERY_LEDGER: ROOT / "templates/discovery-ledger.md",
    SPEC_READINESS: ROOT / "templates/spec-readiness.md",
}

ALLOWED_SUBPHASES = {
    "not-started",
    "intake",
    "discovery",
    "spec-drafting",
    "spec-review",
    "ready-for-activation",
    "activated",
}

REQUIRED_PRODUCT_CHAPTERS = [
    "01-product-scope.md",
    "02-domain-model.md",
    "03-permissions-and-identity.md",
    "04-user-journeys-and-ui.md",
    "05-business-rules-and-calculations.md",
    "06-api-contracts.md",
    "07-data-and-events.md",
    "08-implementation-guidance.md",
    "09-acceptance-criteria.md",
    "10-open-decisions.md",
    "11-adr.md",
    "12-ui-ux-design.md",
    "13-security-and-compliance.md",
]

REQUIRED_ENGINEERING_ROWS = {
    "validation matrix",
    "project manifest",
    "agent policy",
    "ci and gates",
}

PLACEHOLDER_PATTERN = re.compile(
    r"EXAMPLE_ONLY|PLACEHOLDER|EntityName|EntityStatus|EntitySummaryView|"
    r"GOAL-001|NOGOAL-001|ROLE-001|SCN-001|BC-001|DM-INV-001|"
    r"PERM-001|PERM-002|UI-001|UI-002|JRN-001|"
    r"RULE-STATE-001|RULE-CALC-001|RULE-TIME-001|/api/entities|"
    r"example-service|EVT-001|AC-001|AC-002|OD-001|PV-AREA-001|"
    r"SEC-REQ-001|DATA-CLASS-001|THREAT-001"
)


class AdoptionError(Exception):
    pass


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise AdoptionError(f"missing required file: {path.relative_to(ROOT)}") from exc
    except json.JSONDecodeError as exc:
        raise AdoptionError(f"invalid JSON in {path.relative_to(ROOT)}: {exc}") from exc
    if not isinstance(value, dict):
        raise AdoptionError(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def project_mode() -> str:
    text = STATUS_PATH.read_text(encoding="utf-8")
    match = re.search(r"^\s*mode\s*:\s*(framework|adoption|project)\s*$", text, re.MULTILINE)
    if not match:
        raise AdoptionError("docs/product-spec/PROJECT-STATUS.md must declare mode: framework, adoption, or project")
    return match.group(1)


def set_project_mode(mode: str) -> None:
    text = STATUS_PATH.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"(^\s*mode\s*:\s*)(framework|adoption|project)(\s*$)",
        rf"\g<1>{mode}\3",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise AdoptionError("could not update docs/product-spec/PROJECT-STATUS.md mode")
    STATUS_PATH.write_text(updated, encoding="utf-8")


def normalize_cell(value: str) -> str:
    return value.strip().strip("`").strip().lower()


READINESS_HEADER_ALIASES = {
    "chapter": "chapter",
    "chapter or area": "chapter",
    "area": "area",
    "分卷": "chapter",
    "章节": "chapter",
    "领域": "area",
    "分卷或领域": "chapter",
    "required content": "required content",
    "required content before project mode": "required content",
    "必需内容": "required content",
    "project mode 前必需内容": "required content",
    "状态": "status",
    "status": "status",
    "blocking gap?": "blocking gap?",
    "blocking?": "blocking gap?",
    "是否阻塞缺口": "blocking gap?",
    "是否阻塞": "blocking gap?",
    "next action": "next action",
    "下一步": "next action",
    "下一步动作": "next action",
}


def canonical_readiness_header(value: str) -> str:
    normalized = normalize_cell(value)
    return READINESS_HEADER_ALIASES.get(normalized, normalized)


def strip_markdown_noise(text: str) -> str:
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    text = re.sub(r"[#>*`|\-\[\]]", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def ensure_adoption_files() -> list[str]:
    created: list[str] = []
    for path, template in ADOPTION_DOCS.items():
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if template.exists():
            shutil.copyfile(template, path)
        else:
            path.write_text("# Adoption document\n", encoding="utf-8")
        created.append(path.relative_to(ROOT).as_posix())
    return created


def ensure_state_shape(state: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if state.get("schema_version") != 1:
        failures.append("harness/adoption-state.json schema_version must be 1")
    project = state.get("project")
    if not isinstance(project, dict):
        failures.append("harness/adoption-state.json project must be an object")
    adoption = state.get("adoption")
    if not isinstance(adoption, dict):
        failures.append("harness/adoption-state.json adoption must be an object")
        return failures
    subphase = adoption.get("subphase")
    if subphase not in ALLOWED_SUBPHASES:
        failures.append(f"adoption.subphase must be one of {sorted(ALLOWED_SUBPHASES)}")
    confirmation = adoption.get("confirmation")
    if not isinstance(confirmation, dict):
        failures.append("adoption.confirmation must be an object")
    blockers = adoption.get("blockers")
    if not isinstance(blockers, list):
        failures.append("adoption.blockers must be an array")
    return failures


def parse_readiness_tables(text: str) -> dict[str, dict[str, str]]:
    rows: dict[str, dict[str, str]] = {}
    headers: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not (line.startswith("|") and line.endswith("|")):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if cells and all(re.fullmatch(r":?-{3,}:?", cell.strip()) for cell in cells):
            continue
        normalized = [canonical_readiness_header(cell) for cell in cells]
        if "status" in normalized and normalized[0] in {"chapter", "area"}:
            headers = normalized
            continue
        if not headers or len(cells) < len(headers):
            continue
        key = cells[0].strip().strip("`")
        if not key:
            continue
        row = {headers[index]: cells[index].strip() for index in range(min(len(headers), len(cells)))}
        rows[key.lower()] = row
    return rows


def row_status(row: dict[str, str]) -> str:
    return normalize_cell(row.get("status", ""))


def row_is_blocking(row: dict[str, str]) -> bool:
    value = normalize_cell(row.get("blocking gap?", row.get("blocking?", "")))
    return value in {"yes", "true", "y", "是", "blocking"}


def initial_request_failures() -> list[str]:
    failures: list[str] = []
    if not INITIAL_REQUEST.exists():
        return ["docs/adoption/INITIAL-REQUEST.md is missing"]
    text = INITIAL_REQUEST.read_text(encoding="utf-8")
    normalized = strip_markdown_noise(text)
    if "STARTER_TEMPLATE" in text or "Replace this section" in text or "Example material" in text:
        failures.append("docs/adoption/INITIAL-REQUEST.md still contains starter template markers")
    if len(normalized) < 120:
        failures.append("docs/adoption/INITIAL-REQUEST.md is too sparse to start controlled discovery")
    return failures


def adoption_template_failures() -> list[str]:
    failures: list[str] = []
    for path in (INITIAL_REQUEST, DISCOVERY_LEDGER, SPEC_READINESS):
        if not path.exists():
            failures.append(f"{path.relative_to(ROOT).as_posix()} is missing")
            continue
        text = path.read_text(encoding="utf-8")
        if "STARTER_TEMPLATE" in text:
            failures.append(f"{path.relative_to(ROOT).as_posix()} still contains STARTER_TEMPLATE marker")
    return failures


def readiness_failures(require_activation: bool) -> list[str]:
    if not SPEC_READINESS.exists():
        return ["docs/adoption/SPEC-READINESS.md is missing"]
    rows = parse_readiness_tables(SPEC_READINESS.read_text(encoding="utf-8"))
    failures: list[str] = []
    if not rows:
        return ["docs/adoption/SPEC-READINESS.md has no parseable readiness rows"]

    required_rows = [chapter.lower() for chapter in REQUIRED_PRODUCT_CHAPTERS]
    required_rows.extend(REQUIRED_ENGINEERING_ROWS)
    for key in required_rows:
        row = rows.get(key)
        if not row:
            failures.append(f"spec readiness row is missing: {key}")
            continue
        status = row_status(row)
        if require_activation and status not in {"ready", "not-applicable"}:
            failures.append(f"spec readiness row is not activation-ready: {key} status={status or '<empty>'}")
        if require_activation and row_is_blocking(row):
            failures.append(f"spec readiness row still has a blocking gap: {key}")
    return failures


def placeholder_failures() -> list[str]:
    failures: list[str] = []
    paths = list((ROOT / "docs/product-spec").glob("*.md"))
    paths.append(ROOT / "docs/engineering/06-product-validation-matrix.md")
    for path in sorted(paths):
        if path.name == "PROJECT-STATUS.md":
            continue
        text = path.read_text(encoding="utf-8")
        match = PLACEHOLDER_PATTERN.search(text)
        if match:
            failures.append(f"{path.relative_to(ROOT).as_posix()} contains starter placeholder: {match.group(0)}")
    return failures


def open_decision_failures() -> list[str]:
    path = ROOT / "docs/product-spec/10-open-decisions.md"
    if not path.exists():
        return ["docs/product-spec/10-open-decisions.md is missing"]
    text = path.read_text(encoding="utf-8")
    failures: list[str] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if re.search(r"\|\s*[^|]+\s*\|\s*open\s*\|", line, flags=re.IGNORECASE):
            failures.append(f"blocking open decision remains at docs/product-spec/10-open-decisions.md:{line_number}")
    return failures


def _is_argv(value: Any) -> bool:
    if not (isinstance(value, list) and value and all(isinstance(item, str) and item for item in value)):
        return False
    executable = Path(value[0]).name
    if executable in {"true", "echo", "printf", ":"}:
        return False
    if executable in {"sh", "bash", "zsh"} and len(value) > 1 and value[1] == "-c":
        return False
    return True


def manifest_activation_failures() -> list[str]:
    try:
        manifest = load_json(MANIFEST_PATH)
    except AdoptionError as exc:
        return [str(exc)]
    failures: list[str] = []
    project = manifest.get("project")
    if not isinstance(project, dict):
        failures.append("harness/project-manifest.json project must be an object")
    else:
        if project.get("name") in {"", "HARNESS_STARTER"}:
            failures.append("harness/project-manifest.json project.name must be replaced")
        if project.get("owner") in {"", "UNASSIGNED"}:
            failures.append("harness/project-manifest.json project.owner must be assigned")

    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        failures.append("project activation requires at least one registered component skeleton")
    elif not any(isinstance(component, dict) and component.get("production") is True for component in components):
        failures.append("project activation requires at least one production component")
    if isinstance(components, list):
        for index, component in enumerate(components):
            if not isinstance(component, dict):
                failures.append(f"components[{index}] must be an object")
                continue
            component_path = component.get("path")
            if not isinstance(component_path, str) or not component_path:
                failures.append(f"components[{index}].path is required")
            elif not (ROOT / component_path).is_dir():
                failures.append(f"registered component path does not exist: {component_path}")
            commands = component.get("commands")
            if not isinstance(commands, dict):
                failures.append(f"components[{index}].commands must be an object")
            else:
                for gate in ("lint", "test", "build", "architecture", "security"):
                    if not _is_argv(commands.get(gate)):
                        failures.append(f"components[{index}].commands.{gate} must be a non-empty argv array")

    full_stack = manifest.get("full_stack_e2e")
    if not isinstance(full_stack, dict):
        failures.append("harness/project-manifest.json full_stack_e2e must be an object")
    else:
        if not full_stack.get("compose_files"):
            failures.append("project activation requires full_stack_e2e.compose_files")
        if not full_stack.get("services"):
            failures.append("project activation requires full_stack_e2e.services")
        if not _is_argv(full_stack.get("test_command")):
            failures.append("project activation requires full_stack_e2e.test_command argv")
    return failures


def validation_matrix_failures() -> list[str]:
    path = ROOT / "docs/engineering/06-product-validation-matrix.md"
    if not path.exists():
        return ["docs/engineering/06-product-validation-matrix.md is missing"]
    text = path.read_text(encoding="utf-8")
    failures: list[str] = []
    if "PV-AREA-001" in text:
        failures.append("validation matrix still contains PV-AREA-001 template row")
    if not re.search(r"\bPV-(?!HARNESS\b)[A-Z0-9]+-[0-9]{3}\b", text):
        failures.append("validation matrix must contain at least one real non-harness PV-* row")
    return failures


def confirmation_failures() -> list[str]:
    state = load_json(STATE_PATH)
    adoption = state.get("adoption", {})
    confirmation = adoption.get("confirmation", {}) if isinstance(adoption, dict) else {}
    failures: list[str] = []
    expected_true = {
        "product_spec_reviewed": "product spec must be explicitly reviewed by the user",
        "blocking_open_decisions_closed": "blocking open decisions must be explicitly confirmed closed",
        "approved_for_project_activation": "project activation requires explicit user approval",
    }
    for key, message in expected_true.items():
        if not isinstance(confirmation, dict) or confirmation.get(key) is not True:
            failures.append(message)
    if isinstance(confirmation, dict):
        if not str(confirmation.get("confirmed_by", "")).strip():
            failures.append("activation confirmation must include confirmed_by")
        if len(str(confirmation.get("confirmation_text", "")).strip()) < 20:
            failures.append("activation confirmation text is too short")
    return failures


def collect_failures(require_activation: bool) -> list[str]:
    failures: list[str] = []
    created = ensure_adoption_files()
    if created:
        failures.append(f"created missing adoption files; review them before continuing: {', '.join(created)}")

    try:
        state = load_json(STATE_PATH)
        failures.extend(ensure_state_shape(state))
    except AdoptionError as exc:
        failures.append(str(exc))

    mode = project_mode()
    if require_activation and mode != "adoption":
        failures.append(f"activation check requires mode: adoption, found mode: {mode}")
    elif mode == "framework" and not require_activation:
        return failures

    if mode == "adoption" or require_activation:
        failures.extend(initial_request_failures())
        failures.extend(readiness_failures(require_activation=require_activation))

    if require_activation:
        failures.extend(adoption_template_failures())
        failures.extend(placeholder_failures())
        failures.extend(open_decision_failures())
        failures.extend(validation_matrix_failures())
        failures.extend(manifest_activation_failures())
        failures.extend(confirmation_failures())
    return failures


def print_failures(title: str, failures: list[str]) -> None:
    print(f"{title} failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)


def command_init(args: argparse.Namespace) -> int:
    mode = project_mode()
    if mode == "project":
        raise AdoptionError("cannot start adoption because current mode is already project")
    ensure_adoption_files()

    state = load_json(STATE_PATH)
    failures = ensure_state_shape(state)
    if failures:
        print_failures("start-project", failures)
        return 1
    state["project"] = {"name": args.name, "owner": args.owner}
    state["adoption"]["subphase"] = "intake"
    state["adoption"]["last_started_at"] = now_iso()
    state["adoption"]["last_updated_at"] = now_iso()
    state["adoption"]["confirmation"] = {
        "product_spec_reviewed": False,
        "blocking_open_decisions_closed": False,
        "approved_for_project_activation": False,
        "confirmed_by": "",
        "confirmed_at": "",
        "confirmation_text": "",
    }
    state["adoption"]["blockers"] = [
        "Fill docs/adoption/INITIAL-REQUEST.md with the initial product intent.",
        "Run adoption discovery before writing confirmed facts into docs/product-spec/.",
    ]
    write_json(STATE_PATH, state)

    manifest = load_json(MANIFEST_PATH)
    manifest.setdefault("project", {})
    manifest["project"]["name"] = args.name
    manifest["project"]["owner"] = args.owner
    write_json(MANIFEST_PATH, manifest)

    if mode == "framework":
        set_project_mode("adoption")

    print("start-project completed.")
    print(f"- mode: adoption")
    print(f"- project: {args.name}")
    print(f"- owner: {args.owner}")
    print("- next: fill docs/adoption/INITIAL-REQUEST.md, then run ./scripts/adoption-status.sh")
    return 0


def command_status(_args: argparse.Namespace) -> int:
    mode = project_mode()
    state = load_json(STATE_PATH)
    adoption = state.get("adoption", {})
    project = state.get("project", {})
    print("Adoption status")
    print(f"- mode: {mode}")
    print(f"- project: {project.get('name', '<unknown>')}")
    print(f"- owner: {project.get('owner', '<unknown>')}")
    print(f"- subphase: {adoption.get('subphase', '<unknown>')}")

    failures = collect_failures(require_activation=False)
    if failures:
        print("\nCurrent blockers or required cleanup:")
        for failure in failures:
            print(f"- {failure}")
    else:
        print("\nCurrent adoption workspace checks passed for this mode.")

    activation_failures = collect_failures(require_activation=True) if mode == "adoption" else []
    if activation_failures:
        print("\nActivation blockers:")
        for failure in activation_failures[:20]:
            print(f"- {failure}")
        if len(activation_failures) > 20:
            print(f"- ... {len(activation_failures) - 20} more")
    elif mode == "adoption":
        print("\nActivation check has no blockers. Run ./scripts/activate-project.sh after explicit user approval.")
    return 0


def command_check(args: argparse.Namespace) -> int:
    failures = collect_failures(require_activation=args.activation)
    if failures:
        print_failures("adoption-check", failures)
        return 1
    scope = "activation" if args.activation else "current"
    print(f"adoption-check passed: scope={scope}, mode={project_mode()}.")
    return 0


def run_command(argv: list[str]) -> None:
    print(f"==> {' '.join(argv)}")
    subprocess.run(argv, cwd=ROOT, check=True)


def command_activate(args: argparse.Namespace) -> int:
    if project_mode() != "adoption":
        raise AdoptionError("activate-project requires current mode: adoption")

    state = load_json(STATE_PATH)
    failures = ensure_state_shape(state)
    if failures:
        print_failures("activate-project", failures)
        return 1
    confirmation = state["adoption"]["confirmation"]
    confirmation["product_spec_reviewed"] = True
    confirmation["blocking_open_decisions_closed"] = True
    confirmation["approved_for_project_activation"] = True
    confirmation["confirmed_by"] = args.confirmed_by
    confirmation["confirmed_at"] = now_iso()
    confirmation["confirmation_text"] = args.confirmation_text
    state["adoption"]["subphase"] = "ready-for-activation"
    state["adoption"]["last_updated_at"] = now_iso()
    state["adoption"]["blockers"] = []
    write_json(STATE_PATH, state)

    failures = collect_failures(require_activation=True)
    if failures:
        print_failures("activate-project", failures)
        return 1

    previous_status = STATUS_PATH.read_text(encoding="utf-8")
    try:
        set_project_mode("project")
        run_command(["./scripts/docs-check.sh"])
        run_command(["./scripts/project-manifest-check.sh", "development"])
        run_command(["./scripts/agent-workflow-check.sh"])
    except subprocess.CalledProcessError as exc:
        STATUS_PATH.write_text(previous_status, encoding="utf-8")
        print(f"activate-project failed; PROJECT-STATUS.md rolled back to adoption: {exc}", file=sys.stderr)
        return 1

    state = load_json(STATE_PATH)
    state["adoption"]["subphase"] = "activated"
    state["adoption"]["last_updated_at"] = now_iso()
    write_json(STATE_PATH, state)
    print("activate-project completed: mode=project.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Greenfield starter adoption runtime")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("--name", required=True)
    init_parser.add_argument("--owner", required=True)
    init_parser.set_defaults(func=command_init)

    status_parser = subparsers.add_parser("status")
    status_parser.set_defaults(func=command_status)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--activation", action="store_true")
    check_parser.set_defaults(func=command_check)

    activate_parser = subparsers.add_parser("activate")
    activate_parser.add_argument("--confirmed-by", required=True)
    activate_parser.add_argument("--confirmation-text", required=True)
    activate_parser.set_defaults(func=command_activate)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except AdoptionError as exc:
        print(f"adoption runtime failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
