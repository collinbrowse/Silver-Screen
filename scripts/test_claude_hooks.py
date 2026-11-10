#!/usr/bin/env python3
"""Claude Code hook and switch-reindent tests. Hooks run as subprocesses with the JSON
Claude Code would send; nothing touches the network or a simulator."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import reindent_switch_cases  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOKS = os.path.join(ROOT, ".claude", "hooks")


def run_hook(name: str, payload: dict, cwd: str = ROOT) -> subprocess.CompletedProcess:
    return subprocess.run(
        [os.path.join(HOOKS, name)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        cwd=cwd,
    )


def decision(result: subprocess.CompletedProcess) -> str | None:
    if not result.stdout.strip():
        return None
    return json.loads(result.stdout)["hookSpecificOutput"].get("permissionDecision")


class ReindentTests(unittest.TestCase):
    def test_reindent_singleLineCases_indentsUnderSwitch(self):
        source = "switch kind {\ncase .movie: \"film\"\ncase .tv: \"tv\"\n}\n"
        expected = "switch kind {\n    case .movie: \"film\"\n    case .tv: \"tv\"\n}\n"
        self.assertEqual(reindent_switch_cases.reindent_source(source), expected)

    def test_reindent_multilinePattern_keepsClosingParenWithCase(self):
        source = (
            "switch route {\n"
            "    case .tvSeason(\n"
            "        let id,\n"
            "        let name\n"
            "    ):\n"
            "        Text(name)\n"
            "}\n"
        )
        self.assertEqual(reindent_switch_cases.reindent_source(source), source)

    def test_reindent_enumDeclaration_isUnchanged(self):
        source = "enum Kind {\ncase movie\ncase tv\n}\n"
        self.assertEqual(reindent_switch_cases.reindent_source(source), source)


class FormatHookTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp(dir=os.path.join(ROOT, "SilverScreen"))
        self.addCleanup(shutil.rmtree, self.scratch)

    def write(self, text: str) -> str:
        path = os.path.join(self.scratch, "Sample.swift")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def test_formatHook_misindentedSwitch_rewritesFileAndTellsClaude(self):
        path = self.write("switch kind {\ncase .movie: \"film\"\n}\n")
        result = run_hook("format-swift.sh", {"tool_name": "Edit", "tool_input": {"file_path": path}})
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "switch kind {\n    case .movie: \"film\"\n}\n")
        self.assertIn("reindented", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_formatHook_alreadyFormatted_isSilent(self):
        path = self.write("switch kind {\n    case .movie: \"film\"\n}\n")
        result = run_hook("format-swift.sh", {"tool_name": "Write", "tool_input": {"file_path": path}})
        self.assertEqual(result.stdout.strip(), "")

    def test_formatHook_nonSwiftFile_isSilent(self):
        result = run_hook("format-swift.sh", {"tool_name": "Edit", "tool_input": {"file_path": os.path.join(ROOT, "README.md")}})
        self.assertEqual(result.stdout.strip(), "")


class DependencyHookTests(unittest.TestCase):
    def test_depsHook_podInstall_isDenied(self):
        result = run_hook("block-third-party-deps.sh", {"tool_name": "Bash", "tool_input": {"command": "pod install"}})
        self.assertEqual(decision(result), "deny")

    def test_depsHook_ordinaryCommand_returnsNoDecision(self):
        result = run_hook("block-third-party-deps.sh", {"tool_name": "Bash", "tool_input": {"command": "ls"}})
        self.assertIsNone(decision(result))


class CodeReviewGateTests(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.repo)
        subprocess.run(["git", "init", "-q", "-b", "feature", self.repo], check=True)

    def create_pr(self, tool: str = "Bash") -> subprocess.CompletedProcess:
        tool_input = {"command": "gh pr create --fill"} if tool == "Bash" else {"head": "feature", "base": "main"}
        return run_hook("require-code-review.sh", {"tool_name": tool, "tool_input": tool_input}, cwd=self.repo)

    def test_reviewGate_firstPullRequest_isDeniedWithReviewAsk(self):
        result = self.create_pr()
        self.assertEqual(decision(result), "deny")
        self.assertIn("code-review", result.stdout)

    def test_reviewGate_secondAttemptOnSameBranch_goesThrough(self):
        self.create_pr()
        self.assertIsNone(decision(self.create_pr()))

    def test_reviewGate_githubTool_isGatedToo(self):
        self.assertEqual(decision(self.create_pr("mcp__github__create_pull_request")), "deny")

    def test_reviewGate_otherBashCommand_returnsNoDecision(self):
        result = run_hook("require-code-review.sh", {"tool_name": "Bash", "tool_input": {"command": "gh pr view"}}, cwd=self.repo)
        self.assertIsNone(decision(result))


class ReleaseGateTests(unittest.TestCase):
    def gate(self, command: str) -> str | None:
        return decision(run_hook("gate-release-actions.sh", {"tool_name": "Bash", "tool_input": {"command": command}}))

    def test_releaseGate_cutAndUpload_askTheHuman(self):
        for command in ("python3 scripts/release.py cut", "python3 scripts/release.py archive --upload", "python3 scripts/release.py promote"):
            self.assertEqual(self.gate(command), "ask", command)

    def test_releaseGate_readOnlyReleaseCommands_returnNoDecision(self):
        for command in ("python3 scripts/release.py status", "python3 scripts/release.py check", "python3 scripts/release.py archive"):
            self.assertIsNone(self.gate(command), command)

    def test_releaseGate_releaseTagsAndMain_askTheHuman(self):
        for command in ("git push origin testflight/1.0.0+12", "git push origin v1.0.1", "git push --tags", "git push origin main", "git push origin HEAD:main"):
            self.assertEqual(self.gate(command), "ask", command)

    def test_releaseGate_featureBranchPush_returnsNoDecision(self):
        for command in ("git push -u origin claude/offline", "git push origin claude/v2-mainline"):
            self.assertIsNone(self.gate(command), command)

    def test_releaseGate_mainPrefixedBranch_returnsNoDecision(self):
        self.assertIsNone(self.gate("git push origin main-fix"))

    def test_releaseGate_barePushOnMain_asksTheHuman(self):
        repo = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, repo)
        subprocess.run(["git", "init", "-q", "-b", "main", repo], check=True)
        payload = {"tool_name": "Bash", "tool_input": {"command": "git push"}}
        self.assertEqual(decision(run_hook("gate-release-actions.sh", payload, cwd=repo)), "ask")

    def test_releaseGate_workflowRunAndGhRelease_askTheHuman(self):
        for command in ("gh workflow run release.yml -f ref=testflight/1.0.0+11", "gh workflow run Release", "gh api -X POST repos/a/b/actions/workflows/release.yml/dispatches -f ref=main", "gh api -X POST repos/a/b/actions/runs/42/pending_deployments -f state=approved", "gh release create v1.0.1", "gh api -X POST repos/a/b/git/refs -f ref=refs/tags/x"):
            self.assertEqual(self.gate(command), "ask", command)

    def test_releaseGate_ciWorkflowRun_returnsNoDecision(self):
        self.assertIsNone(self.gate("gh workflow run ci.yml"))

    def test_releaseGate_mergeWithoutAuto_asksTheHuman(self):
        self.assertEqual(self.gate("gh pr merge 5 --merge"), "ask")
        self.assertIsNone(self.gate("gh pr merge 5 --auto --merge"))

    def test_releaseGate_protectionWrites_askTheHuman(self):
        self.assertEqual(self.gate("gh api -X POST repos/a/b/rulesets --input r.json"), "ask")
        self.assertEqual(self.gate("gh api -X PATCH repos/a/b -F allow_auto_merge=true"), "ask")
        self.assertIsNone(self.gate("gh api repos/a/b/rulesets"))
        self.assertIsNone(self.gate("gh api repos/a/b/pulls/3/files"))


class StopHookTests(unittest.TestCase):
    @unittest.skipIf(shutil.which("xcrun"), "a simulator is available; the hook would run the suite")
    def test_stopHook_noSimulator_letsTheTurnEnd(self):
        result = run_hook("run-unit-tests.sh", {"hook_event_name": "Stop", "stop_hook_active": True})
        self.assertEqual((result.returncode, result.stdout.strip()), (0, ""))


if __name__ == "__main__":
    unittest.main()
