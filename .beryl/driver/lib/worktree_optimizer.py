#!/usr/bin/env python3
"""Deterministic DAG validation for optional driver worktree optimization."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


TASK_ID_RE = re.compile(r"^([0-9]+)-.*\.md$")
PLACEHOLDER_SUFFIX = "-placeholder-task.md"
SAFE_BRANCH_RE = re.compile(r"[^A-Za-z0-9._/-]+")


class OptimizationError(RuntimeError):
    """Raised when optimizer input cannot be trusted."""


@dataclass(frozen=True)
class SelectedTask:
    task_id: str
    title: str
    path: str
    brief: str


def task_sort_key(task_id: str) -> tuple[int, str]:
    try:
        return (int(task_id), task_id)
    except ValueError:
        return (sys.maxsize, task_id)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(errors="replace")


def title_from_brief(text: str, fallback: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip() or fallback
    return fallback


def list_selected_tasks(driver_dir: Path, only_task: str | None, from_task: str | None) -> list[SelectedTask]:
    tasks_dir = driver_dir / "tasks"
    selected: list[SelectedTask] = []
    started = from_task is None
    for path in sorted(tasks_dir.glob("[0-9]*.md")):
        match = TASK_ID_RE.match(path.name)
        if not match:
            continue
        if path.name.endswith(PLACEHOLDER_SUFFIX):
            continue
        task_id = match.group(1)
        if only_task and task_id != only_task:
            continue
        if from_task and not started:
            if task_id == from_task:
                started = True
            else:
                continue
        brief = read_text(path)
        selected.append(
            SelectedTask(
                task_id=task_id,
                title=title_from_brief(brief, path.stem),
                path=str(path),
                brief=brief,
            )
        )
    return selected


def task_payload(tasks: list[SelectedTask]) -> dict[str, Any]:
    return {
        "tasks": [
            {
                "id": task.task_id,
                "title": task.title,
                "path": task.path,
                "brief": task.brief,
            }
            for task in tasks
        ]
    }


def task_summary_payload(tasks: list[SelectedTask]) -> dict[str, Any]:
    return {
        "tasks": [
            {
                "id": task.task_id,
                "title": task.title,
                "path": task.path,
            }
            for task in tasks
        ]
    }


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise OptimizationError(f"invalid JSON in {path}: {exc}") from exc


def extract_json_object(text: str) -> dict[str, Any]:
    text = text.strip()
    if not text:
        raise OptimizationError("optimizer produced no output")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise OptimizationError("optimizer output did not contain a JSON object")
        try:
            data = json.loads(text[start : end + 1])
        except json.JSONDecodeError as exc:
            raise OptimizationError(f"optimizer output did not contain parseable JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise OptimizationError("optimizer JSON must be an object")
    return data


def normalize_task_id(value: Any, field: str) -> str:
    if isinstance(value, int):
        return f"{value:02d}"
    if isinstance(value, str):
        stripped = value.strip()
        if stripped:
            return stripped
    raise OptimizationError(f"dependency field {field!r} must be a non-empty task id")


def normalize_nodes(raw: dict[str, Any], expected_ids: set[str]) -> list[str]:
    raw_nodes = raw.get("tasks", raw.get("nodes"))
    if not isinstance(raw_nodes, list):
        raise OptimizationError("optimizer JSON must include a tasks or nodes list")
    node_ids: list[str] = []
    seen: set[str] = set()
    for node in raw_nodes:
        if isinstance(node, dict):
            value = node.get("id")
        else:
            value = node
        task_id = normalize_task_id(value, "id")
        if task_id in seen:
            raise OptimizationError(f"duplicate task node: {task_id}")
        seen.add(task_id)
        node_ids.append(task_id)
    actual = set(node_ids)
    missing = sorted(expected_ids - actual, key=task_sort_key)
    unknown = sorted(actual - expected_ids, key=task_sort_key)
    if missing:
        raise OptimizationError(f"optimizer DAG is missing selected task node(s): {', '.join(missing)}")
    if unknown:
        raise OptimizationError(f"optimizer DAG includes unknown task node(s): {', '.join(unknown)}")
    return sorted(node_ids, key=task_sort_key)


def edge_value(edge: dict[str, Any], *names: str) -> Any:
    for name in names:
        if name in edge:
            return edge[name]
    return None


def normalize_edges(raw: dict[str, Any], expected_ids: set[str]) -> list[dict[str, str]]:
    raw_edges = raw.get("dependencies", raw.get("edges", []))
    if raw_edges is None:
        raw_edges = []
    if not isinstance(raw_edges, list):
        raise OptimizationError("dependencies must be a list")

    dependencies: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for edge in raw_edges:
        if not isinstance(edge, dict):
            raise OptimizationError("each dependency must be an object")
        before = normalize_task_id(edge_value(edge, "before", "from", "source", "depends_on"), "before")
        after = normalize_task_id(edge_value(edge, "after", "to", "target", "task"), "after")
        if before == after:
            raise OptimizationError(f"self dependency is not allowed: {before}")
        unknown = [task_id for task_id in (before, after) if task_id not in expected_ids]
        if unknown:
            raise OptimizationError(f"dependency references unknown task node(s): {', '.join(sorted(set(unknown), key=task_sort_key))}")
        pair = (before, after)
        if pair in seen:
            raise OptimizationError(f"duplicate dependency is not allowed: {before}->{after}")
        seen.add(pair)
        dependencies.append(
            {
                "before": before,
                "after": after,
                "rationale": str(edge.get("rationale") or "").strip(),
            }
        )
    return sorted(dependencies, key=lambda item: (task_sort_key(item["before"]), task_sort_key(item["after"])))


def compute_waves(node_ids: list[str], dependencies: list[dict[str, str]]) -> list[list[str]]:
    outgoing: dict[str, set[str]] = {task_id: set() for task_id in node_ids}
    indegree: dict[str, int] = {task_id: 0 for task_id in node_ids}
    for edge in dependencies:
        before = edge["before"]
        after = edge["after"]
        outgoing[before].add(after)
        indegree[after] += 1

    remaining = set(node_ids)
    waves: list[list[str]] = []
    while remaining:
        ready = sorted([task_id for task_id in remaining if indegree[task_id] == 0], key=task_sort_key)
        if not ready:
            cycle_nodes = ", ".join(sorted(remaining, key=task_sort_key))
            raise OptimizationError(f"dependency cycle detected involving: {cycle_nodes}")
        waves.append(ready)
        for task_id in ready:
            remaining.remove(task_id)
            for dependent in outgoing[task_id]:
                indegree[dependent] -= 1
    return waves


def verify_dag(tasks_data: dict[str, Any], raw_data: dict[str, Any]) -> dict[str, Any]:
    selected = tasks_data.get("tasks")
    if not isinstance(selected, list):
        raise OptimizationError("tasks.json must contain a tasks list")
    selected_ids = [normalize_task_id(task.get("id") if isinstance(task, dict) else task, "id") for task in selected]
    if len(selected_ids) != len(set(selected_ids)):
        raise OptimizationError("selected task list contains duplicate ids")
    expected_ids = set(selected_ids)
    node_ids = normalize_nodes(raw_data, expected_ids)
    dependencies = normalize_edges(raw_data, expected_ids)
    waves = compute_waves(node_ids, dependencies)
    return {
        "status": "verified",
        "tasks": [
            {
                "id": task_id,
                "title": next(
                    (str(task.get("title") or "") for task in selected if isinstance(task, dict) and normalize_task_id(task.get("id"), "id") == task_id),
                    "",
                ),
            }
            for task_id in node_ids
        ],
        "dependencies": dependencies,
        "waves": waves,
        "parallelizable": any(len(wave) > 1 for wave in waves),
    }


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_waves(path: Path, waves: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"wave {index}: {' '.join(wave)}" for index, wave in enumerate(waves, start=1)]
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def safe_branch_name(work_branch: str, task_id: str) -> str:
    cleaned = SAFE_BRANCH_RE.sub("-", work_branch.strip()).strip("/.-")
    return f"{cleaned or 'driver-work'}-task-{task_id}"


def parallel_task_ids(verified: dict[str, Any]) -> list[str]:
    waves = verified.get("waves")
    if not isinstance(waves, list):
        raise OptimizationError("verified DAG must include waves")
    ids: list[str] = []
    for wave in waves:
        if not isinstance(wave, list):
            raise OptimizationError("verified DAG waves must be lists")
        normalized = [normalize_task_id(task_id, "wave") for task_id in wave]
        if len(normalized) > 1:
            ids.extend(normalized)
    return ids


def write_worktrees(path: Path, records: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not records:
        path.write_text("none\n", encoding="utf-8")
        return
    path.write_text(
        "".join(f"{record['task']} {record['branch']} {record['path']}\n" for record in records),
        encoding="utf-8",
    )


def command_prepare_worktrees(args: argparse.Namespace) -> int:
    verified = load_json(Path(args.verified_json))
    task_ids = parallel_task_ids(verified)
    records: list[dict[str, str]] = []
    root = Path(args.worktree_root).resolve()

    if task_ids:
        root.mkdir(parents=True, exist_ok=True)

    for task_id in task_ids:
        branch = safe_branch_name(args.work_branch, task_id)
        path = root / f"task-{task_id}"
        if args.mock:
            records.append({"task": task_id, "branch": branch, "path": str(path)})
            continue
        if path.exists():
            raise OptimizationError(f"worktree path already exists: {path}")
        branch_exists = subprocess.run(
            ["git", "-C", args.repo_root, "rev-parse", "--verify", branch],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        ).returncode == 0
        if branch_exists:
            raise OptimizationError(f"worktree branch already exists: {branch}")
        try:
            subprocess.run(
                ["git", "-C", args.repo_root, "worktree", "add", "-b", branch, str(path), args.work_branch],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr.strip() or exc.stdout.strip() or f"exit code {exc.returncode}"
            raise OptimizationError(f"failed to create worktree for task {task_id}: {detail}") from exc
        records.append({"task": task_id, "branch": branch, "path": str(path)})

    write_worktrees(Path(args.output), records)
    return 0


def mock_dag(tasks_data: dict[str, Any]) -> dict[str, Any]:
    selected = tasks_data.get("tasks")
    if not isinstance(selected, list):
        raise OptimizationError("tasks.json must contain a tasks list")
    return {
        "tasks": [{"id": normalize_task_id(task.get("id") if isinstance(task, dict) else task, "id")} for task in selected],
        "dependencies": [],
    }


def command_list(args: argparse.Namespace) -> int:
    tasks = list_selected_tasks(Path(args.driver_dir), args.only_task, args.from_task)
    payload = task_payload(tasks) if args.include_briefs else task_summary_payload(tasks)
    write_json(Path(args.output), payload)
    return 0


def command_extract(args: argparse.Namespace) -> int:
    data = extract_json_object(Path(args.input).read_text(encoding="utf-8"))
    write_json(Path(args.output), data)
    return 0


def command_mock(args: argparse.Namespace) -> int:
    tasks_data = load_json(Path(args.tasks_json))
    write_json(Path(args.output), mock_dag(tasks_data))
    return 0


def command_verify(args: argparse.Namespace) -> int:
    tasks_data = load_json(Path(args.tasks_json))
    raw_data = load_json(Path(args.raw_json))
    verified = verify_dag(tasks_data, raw_data)
    write_json(Path(args.output), verified)
    write_waves(Path(args.waves_txt), verified["waves"])
    return 0


def assert_error_contains(description: str, needle: str, func: Any, *args: Any) -> None:
    try:
        func(*args)
    except OptimizationError as exc:
        if needle not in str(exc):
            raise AssertionError(f"{description}: error {exc!r} did not contain {needle!r}") from exc
        return
    raise AssertionError(f"{description}: expected OptimizationError")


def run_selftest() -> int:
    tasks = {
        "tasks": [
            {"id": "01", "title": "One"},
            {"id": "02", "title": "Two"},
            {"id": "03", "title": "Three"},
        ]
    }

    independent = verify_dag(tasks, {"tasks": [{"id": "01"}, {"id": "02"}, {"id": "03"}], "dependencies": []})
    assert independent["waves"] == [["01", "02", "03"]]
    assert independent["parallelizable"] is True

    serial = verify_dag(
        tasks,
        {
            "nodes": ["01", "02", "03"],
            "edges": [
                {"before": "01", "after": "02", "rationale": "two uses one"},
                {"before": "02", "after": "03", "rationale": "three uses two"},
            ],
        },
    )
    assert serial["waves"] == [["01"], ["02"], ["03"]]
    assert serial["parallelizable"] is False

    assert_error_contains(
        "unknown node rejection",
        "unknown task node",
        verify_dag,
        tasks,
        {"tasks": [{"id": "01"}, {"id": "02"}, {"id": "03"}, {"id": "99"}], "dependencies": []},
    )
    assert_error_contains(
        "cycle rejection",
        "cycle",
        verify_dag,
        tasks,
        {
            "tasks": ["01", "02", "03"],
            "dependencies": [
                {"before": "01", "after": "02"},
                {"before": "02", "after": "01"},
            ],
        },
    )
    assert_error_contains(
        "duplicate dependency rejection",
        "duplicate dependency",
        verify_dag,
        tasks,
        {
            "tasks": ["01", "02", "03"],
            "dependencies": [
                {"before": "01", "after": "02"},
                {"before": "01", "after": "02"},
            ],
        },
    )
    assert_error_contains(
        "self dependency rejection",
        "self dependency",
        verify_dag,
        tasks,
        {"tasks": ["01", "02", "03"], "dependencies": [{"before": "01", "after": "01"}]},
    )
    assert_error_contains(
        "incomplete node rejection",
        "missing selected task",
        verify_dag,
        tasks,
        {"tasks": ["01", "02"], "dependencies": []},
    )

    single = verify_dag({"tasks": [{"id": "07", "title": "Single"}]}, {"tasks": [{"id": "07"}], "dependencies": []})
    assert single["waves"] == [["07"]]
    assert single["parallelizable"] is False

    with tempfile.TemporaryDirectory() as tmp:
        driver_dir = Path(tmp) / ".beryl" / "driver"
        tasks_dir = driver_dir / "tasks"
        tasks_dir.mkdir(parents=True)
        (tasks_dir / "01-one.md").write_text("# One\n", encoding="utf-8")
        (tasks_dir / "02-placeholder-task.md").write_text("# Placeholder\n", encoding="utf-8")
        (tasks_dir / "03-three.md").write_text("# Three\n", encoding="utf-8")
        listed = list_selected_tasks(driver_dir, None, "03")
        assert [task.task_id for task in listed] == ["03"]

        verified_path = driver_dir / "state" / "optimization" / "dag.verified.json"
        worktrees_path = driver_dir / "state" / "optimization" / "worktrees.txt"
        write_json(verified_path, independent)
        command_prepare_worktrees(
            argparse.Namespace(
                verified_json=str(verified_path),
                output=str(worktrees_path),
                worktree_root=str(Path(tmp) / "worktrees"),
                work_branch="feat/example",
                repo_root=str(Path(tmp)),
                mock=True,
            )
        )
        assert "feat/example-task-01" in worktrees_path.read_text(encoding="utf-8")

    print("worktree_optimizer selftest: PASS")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="write selected driver tasks as JSON")
    list_parser.add_argument("--driver-dir", required=True)
    list_parser.add_argument("--output", required=True)
    list_parser.add_argument("--task", dest="only_task")
    list_parser.add_argument("--from", dest="from_task")
    list_parser.add_argument("--include-briefs", action="store_true")
    list_parser.set_defaults(func=command_list)

    extract_parser = subparsers.add_parser("extract-json", help="extract a JSON object from agent output")
    extract_parser.add_argument("--input", required=True)
    extract_parser.add_argument("--output", required=True)
    extract_parser.set_defaults(func=command_extract)

    mock_parser = subparsers.add_parser("mock-dag", help="write a deterministic independent-task DAG")
    mock_parser.add_argument("--tasks-json", required=True)
    mock_parser.add_argument("--output", required=True)
    mock_parser.set_defaults(func=command_mock)

    verify_parser = subparsers.add_parser("verify", help="verify optimizer DAG JSON and compute waves")
    verify_parser.add_argument("--tasks-json", required=True)
    verify_parser.add_argument("--raw-json", required=True)
    verify_parser.add_argument("--output", required=True)
    verify_parser.add_argument("--waves-txt", required=True)
    verify_parser.set_defaults(func=command_verify)

    worktree_parser = subparsers.add_parser("prepare-worktrees", help="create worktrees for verified parallel waves")
    worktree_parser.add_argument("--verified-json", required=True)
    worktree_parser.add_argument("--output", required=True)
    worktree_parser.add_argument("--worktree-root", required=True)
    worktree_parser.add_argument("--work-branch", required=True)
    worktree_parser.add_argument("--repo-root", required=True)
    worktree_parser.add_argument("--mock", action="store_true")
    worktree_parser.set_defaults(func=command_prepare_worktrees)

    selftest_parser = subparsers.add_parser("selftest", help="run deterministic optimizer selftests")
    selftest_parser.set_defaults(func=lambda _args: run_selftest())

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except OptimizationError as exc:
        print(f"worktree optimizer: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
