"""Tests for scripts/resolve-plan-dir.sh — addresses #148.

Resolver order:
  1. $KNOT_PLANNING_TASK_DIR if it contains task_plan.md
  2. $PLAN_ID env under Knot scope-aware .state/tasks roots
  3. Knot .state/tasks/.active_task under actor/user/current workspace roots
  4. $PLAN_ID env → .planning/<id>/ if it contains task_plan.md
  5. .planning/.active_plan content → .planning/<id>/ if it contains task_plan.md
  6. Newest .planning/<dir>/ by mtime
  7. .state/ if it contains task_plan.md
  8. Otherwise empty stdout, exit 0
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RESOLVE_SH = REPO_ROOT / "scripts" / "resolve-plan-dir.sh"


class ResolvePlanDirTests(unittest.TestCase):
    def run_resolver(
        self,
        cwd: Path,
        plan_id: str | None = None,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        for key in (
            "PLAN_ID",
            "KNOT_PLANNING_TASK_DIR",
            "KNOT_ACTOR_WORKSPACE",
            "KNOT_USER_WORKSPACE",
            "KNOT_ACTIVE_WORKSPACE",
            "KNOT_ROOT",
        ):
            env.pop(key, None)
        if plan_id is not None:
            env["PLAN_ID"] = plan_id
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["sh", str(RESOLVE_SH)],
            cwd=str(cwd),
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def test_resolver_script_exists(self) -> None:
        self.assertTrue(RESOLVE_SH.exists(), "scripts/resolve-plan-dir.sh missing")

    def test_empty_repo_returns_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_resolver(Path(tmp))
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("", result.stdout.strip())

    def test_env_plan_id_takes_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".planning" / "alpha").mkdir(parents=True)
            (root / ".planning" / "alpha" / "task_plan.md").write_text("# alpha\n", encoding="utf-8")
            (root / ".planning" / "beta").mkdir(parents=True)
            (root / ".planning" / "beta" / "task_plan.md").write_text("# beta\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("beta\n", encoding="utf-8")
            result = self.run_resolver(root, plan_id="alpha")
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(result.stdout.strip().endswith("alpha"))

    def test_knot_planning_task_dir_takes_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            knot_task = root / "workspace" / "users" / "member" / ".state" / "tasks" / "knot-task"
            legacy_task = root / ".planning" / "legacy"
            knot_task.mkdir(parents=True)
            legacy_task.mkdir(parents=True)
            (knot_task / "task_plan.md").write_text("# knot\n", encoding="utf-8")
            (legacy_task / "task_plan.md").write_text("# legacy\n", encoding="utf-8")
            result = self.run_resolver(
                root,
                plan_id="legacy",
                extra_env={"KNOT_PLANNING_TASK_DIR": str(knot_task)},
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(str(knot_task), result.stdout.strip())

    def test_knot_plan_id_uses_scope_aware_task_roots(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            actor_workspace = root / "workspace" / "groups" / "product" / "work" / "member"
            task = actor_workspace / ".state" / "tasks" / "scoped-task"
            task.mkdir(parents=True)
            (task / "task_plan.md").write_text("# scoped\n", encoding="utf-8")
            result = self.run_resolver(
                root,
                plan_id="scoped-task",
                extra_env={"KNOT_ACTOR_WORKSPACE": str(actor_workspace)},
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(str(task), result.stdout.strip())

    def test_knot_active_task_file_uses_scope_aware_task_roots(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            user_workspace = root / "workspace" / "users" / "member"
            task_root = user_workspace / ".state" / "tasks"
            task = task_root / "active-task"
            task.mkdir(parents=True)
            (task / "task_plan.md").write_text("# active\n", encoding="utf-8")
            (task_root / ".active_task").write_text("active-task\n", encoding="utf-8")
            result = self.run_resolver(root, extra_env={"KNOT_USER_WORKSPACE": str(user_workspace)})
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(str(task), result.stdout.strip())

    def test_active_plan_used_when_env_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".planning" / "alpha").mkdir(parents=True)
            (root / ".planning" / "alpha" / "task_plan.md").write_text("# alpha\n", encoding="utf-8")
            (root / ".planning" / "beta").mkdir(parents=True)
            (root / ".planning" / "beta" / "task_plan.md").write_text("# beta\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("beta\n", encoding="utf-8")
            result = self.run_resolver(root)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(result.stdout.strip().endswith("beta"))

    def test_falls_back_to_newest_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            old = root / ".planning" / "older"
            new = root / ".planning" / "newer"
            old.mkdir(parents=True)
            (old / "task_plan.md").write_text("# old\n", encoding="utf-8")
            time.sleep(0.05)
            new.mkdir(parents=True)
            (new / "task_plan.md").write_text("# new\n", encoding="utf-8")
            # bump mtime explicitly to be safe across filesystems
            os.utime(new, None)
            result = self.run_resolver(root)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(
                result.stdout.strip().endswith("newer"),
                f"expected newer, got {result.stdout!r}",
            )

    def test_legacy_root_plan_emits_empty(self) -> None:
        # When no .planning/ but cwd/task_plan.md exists, resolver emits empty so
        # callers fall back to the legacy root path. This preserves v1.x users.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "task_plan.md").write_text("# legacy\n", encoding="utf-8")
            result = self.run_resolver(root)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("", result.stdout.strip())

    def test_env_plan_id_pointing_to_missing_dir_falls_through(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real = root / ".planning" / "real"
            real.mkdir(parents=True)
            (real / "task_plan.md").write_text("# real plan\n", encoding="utf-8")
            result = self.run_resolver(root, plan_id="ghost")
            self.assertEqual(0, result.returncode, result.stderr)
            # Should fall through to newest existing plan dir
            self.assertTrue(result.stdout.strip().endswith("real"))

    def test_env_plan_id_without_task_plan_falls_through(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".planning" / "empty").mkdir(parents=True)
            real = root / ".planning" / "real"
            real.mkdir(parents=True)
            (real / "task_plan.md").write_text("# real plan\n", encoding="utf-8")
            result = self.run_resolver(root, plan_id="empty")
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(result.stdout.strip().endswith("real"))

    def test_active_plan_without_task_plan_falls_through(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".planning" / "empty").mkdir(parents=True)
            real = root / ".planning" / "real"
            real.mkdir(parents=True)
            (real / "task_plan.md").write_text("# real plan\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("empty\n", encoding="utf-8")
            result = self.run_resolver(root)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(result.stdout.strip().endswith("real"))

    def test_plan_id_path_traversal_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outside = root / "outside"
            outside.mkdir()
            (outside / "task_plan.md").write_text("# outside\n", encoding="utf-8")
            real = root / ".planning" / "real"
            real.mkdir(parents=True)
            (real / "task_plan.md").write_text("# real plan\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("../outside\n", encoding="utf-8")

            active_result = self.run_resolver(root)
            env_result = self.run_resolver(root, plan_id="../outside")

            self.assertEqual(0, active_result.returncode, active_result.stderr)
            self.assertEqual(0, env_result.returncode, env_result.stderr)
            self.assertTrue(active_result.stdout.strip().endswith("real"))
            self.assertTrue(env_result.stdout.strip().endswith("real"))


if __name__ == "__main__":
    unittest.main()
