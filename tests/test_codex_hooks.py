import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CODEX_ROOT = REPO_ROOT / ".codex"
HOOKS_JSON = CODEX_ROOT / "hooks.json"
HOOKS_DIR = CODEX_ROOT / "hooks"
CODEX_SKILL = CODEX_ROOT / "skills" / "planning-with-files"
CODEX_SKILL_MD = CODEX_SKILL / "SKILL.md"
CODEX_SKILL_SCRIPTS = CODEX_SKILL / "scripts"


class CodexHooksTests(unittest.TestCase):
    def run_python_hook(self, script_name: str, payload: dict, cwd: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(HOOKS_DIR / script_name)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            cwd=str(cwd),
            check=False,
        )

    def run_shell_hook(self, script_name: str, cwd: Path, env: dict | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(HOOKS_DIR / script_name)],
            text=True,
            capture_output=True,
            cwd=str(cwd),
            env=env,
            check=False,
        )

    def run_skill_script(self, script_name: str, cwd: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(CODEX_SKILL_SCRIPTS / script_name)],
            text=True,
            capture_output=True,
            cwd=str(cwd),
            check=False,
        )

    def test_hooks_json_declares_all_expected_codex_events(self) -> None:
        self.assertTrue(HOOKS_JSON.exists(), ".codex/hooks.json is missing")

        payload = json.loads(HOOKS_JSON.read_text(encoding="utf-8"))
        self.assertEqual(
            {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"},
            set(payload["hooks"]),
        )

    def test_skill_frontmatter_hooks_route_through_codex_scripts(self) -> None:
        skill_md = CODEX_SKILL_MD.read_text(encoding="utf-8")
        for script in ("user-prompt-submit.sh", "pre-tool-use.sh", "post-tool-use.sh", "stop.sh"):
            self.assertIn(f"$SD/{script}", skill_md)
        self.assertNotIn("if [ -f .state/task_plan.md ]", skill_md)

    def test_session_start_reuses_plan_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir, tempfile.TemporaryDirectory() as home:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text(
                "# Task Plan\n\n## Goal\nShip Codex hooks\n",
                encoding="utf-8",
            )
            state_dir.joinpath("progress.md").write_text(
                "# Progress\n\nFinished adapter draft.\n",
                encoding="utf-8",
            )
            state_dir.joinpath("findings.md").write_text(
                "# Findings\n\n- reuse cursor hooks\n",
                encoding="utf-8",
            )

            env = os.environ.copy()
            env["HOME"] = home
            result = self.run_shell_hook("session-start.sh", root, env=env)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("ACTIVE PLAN", result.stdout)
        self.assertIn("Ship Codex hooks", result.stdout)
        self.assertIn("Finished adapter draft", result.stdout)

    def test_active_planning_dir_takes_precedence_over_state_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text("# State Plan\n", encoding="utf-8")
            state_dir.joinpath("progress.md").write_text("# State Progress\n", encoding="utf-8")

            plan_dir = root / ".planning" / "feature-a"
            plan_dir.mkdir(parents=True)
            plan_dir.joinpath("task_plan.md").write_text("# Planning Plan\n", encoding="utf-8")
            plan_dir.joinpath("progress.md").write_text("# Planning Progress\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("feature-a\n", encoding="utf-8")

            result = self.run_shell_hook("user-prompt-submit.sh", root)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Planning Plan", result.stdout)
        self.assertNotIn("State Plan", result.stdout)

    def test_stale_active_plan_falls_back_to_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text("# State Plan\n", encoding="utf-8")
            state_dir.joinpath("progress.md").write_text("# State Progress\n", encoding="utf-8")

            empty_plan_dir = root / ".planning" / "empty"
            empty_plan_dir.mkdir(parents=True)
            (root / ".planning" / ".active_plan").write_text("empty\n", encoding="utf-8")

            result = self.run_shell_hook("user-prompt-submit.sh", root)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("State Plan", result.stdout)

    def test_knot_actor_lane_task_is_resolved_by_hook(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            actor = root / "workspace/groups/team/work/member"
            task_dir = actor / ".state/tasks/group-task"
            task_dir.mkdir(parents=True)
            task_dir.joinpath("task_plan.md").write_text("# Group Actor Plan\n", encoding="utf-8")
            task_dir.joinpath("progress.md").write_text("# Progress\n", encoding="utf-8")
            task_dir.parent.joinpath(".active_task").write_text("group-task\n", encoding="utf-8")

            env = {**os.environ, "KNOT_ACTOR_WORKSPACE": str(actor)}
            result = self.run_shell_hook("user-prompt-submit.sh", root, env=env)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Group Actor Plan", result.stdout)

    def test_knot_root_task_is_resolved_by_hook(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            task_dir = root / "workspace/.state/tasks/root-task"
            task_dir.mkdir(parents=True)
            task_dir.joinpath("task_plan.md").write_text("# Root Operator Plan\n", encoding="utf-8")
            task_dir.joinpath("progress.md").write_text("# Progress\n", encoding="utf-8")
            task_dir.parent.joinpath(".active_task").write_text("root-task\n", encoding="utf-8")

            env = {**os.environ, "KNOT_ROOT": str(root)}
            result = self.run_shell_hook("user-prompt-submit.sh", root, env=env)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Root Operator Plan", result.stdout)

    def test_codex_skill_script_uses_resolver_and_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text("# State Plan\n", encoding="utf-8")
            state_dir.joinpath("progress.md").write_text("# State Progress\n", encoding="utf-8")

            plan_dir = root / ".planning" / "feature-a"
            plan_dir.mkdir(parents=True)
            plan_dir.joinpath("task_plan.md").write_text("# Planning Plan\n", encoding="utf-8")
            plan_dir.joinpath("progress.md").write_text("# Planning Progress\n", encoding="utf-8")
            plan_dir.joinpath(".attestation").write_text("not-the-current-hash\n", encoding="utf-8")
            (root / ".planning" / ".active_plan").write_text("feature-a\n", encoding="utf-8")

            result = self.run_skill_script("user-prompt-submit.sh", root)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("PLAN TAMPERED", result.stdout)
        self.assertNotIn("Planning Plan", result.stdout)
        self.assertNotIn("State Plan", result.stdout)

    def test_pre_tool_use_adapter_emits_system_message(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text(
                textwrap.dedent(
                    """\
                    # Task Plan
                    ### Phase 1: Discovery
                    - **Status:** complete
                    """
                ),
                encoding="utf-8",
            )

            result = self.run_python_hook(
                "pre_tool_use.py",
                {"cwd": str(root), "tool_input": {"command": "pwd"}},
                root,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIn("systemMessage", payload)
        self.assertIn("# Task Plan", payload["systemMessage"])

    def test_post_tool_use_adapter_emits_progress_reminder(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text("# Task Plan\n", encoding="utf-8")

            result = self.run_python_hook(
                "post_tool_use.py",
                {"cwd": str(root), "tool_response": "ok"},
                root,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIn(".state/progress.md", payload["systemMessage"])

    def test_stop_adapter_blocks_once_then_allows_reentry(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            state_dir = root / ".state"
            state_dir.mkdir()
            state_dir.joinpath("task_plan.md").write_text(
                textwrap.dedent(
                    """\
                    ### Phase 1: Discovery
                    - **Status:** complete

                    ### Phase 2: Implementation
                    - **Status:** pending
                    """
                ),
                encoding="utf-8",
            )

            first = self.run_python_hook(
                "stop.py",
                {"cwd": str(root), "stop_hook_active": False},
                root,
            )
            second = self.run_python_hook(
                "stop.py",
                {"cwd": str(root), "stop_hook_active": True},
                root,
            )

        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(0, second.returncode, second.stderr)

        first_payload = json.loads(first.stdout)
        second_payload = json.loads(second.stdout)

        self.assertEqual("block", first_payload["decision"])
        self.assertIn("Task incomplete", first_payload["reason"])
        self.assertIn("Task incomplete", second_payload["systemMessage"])


if __name__ == "__main__":
    unittest.main()
