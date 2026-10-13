"""Exercise CI guards and sync behavior without a registry, server or Git writes."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
if os.name == "nt":
    # Windows' bash.exe may point to an unconfigured WSL installation. Prefer
    # Git for Windows' Bash, which can run these tests without a Linux VM.
    git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    BASH = str(git_bash) if git_bash.exists() else None


@unittest.skipUnless(BASH, "Bash is required for the shell-script tests")
class ScriptTests(unittest.TestCase):
    def run_script(self, script, settings=None, mock_directory=None):
        environment = os.environ.copy()
        environment.update({
            "HOSTING_ENABLED": "false", "SYNC_ENABLED": "false",
            "CI_COMMIT_MESSAGE": "", "CI_COMMIT_REF_PROTECTED": "false",
        })
        environment.update(settings or {})
        if mock_directory:
            # A fake Git executable returns controlled responses. It never writes
            # .git files or contacts GitHub/GitLab, even in the successful-sync test.
            command = [BASH, "-c", 'cd "$1"; export PATH="$PWD:$PATH"; cd "$2"; exec bash "$3"',
                       "script-test", str(mock_directory), str(ROOT), f"scripts/{script}"]
        else:
            command = [BASH, f"scripts/{script}"]
        return subprocess.run(command, cwd=ROOT, env=environment, text=True,
                              capture_output=True, timeout=20)

    def test_build_is_disabled_by_default(self):
        result = self.run_script("build.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Hosting is not enabled", result.stderr)

    def test_release_marker_is_literal(self):
        for message in ("deploy", "[deployment]", "[deployx]", "[DEPLOY]"):
            with self.subTest(message=message):
                result = self.run_script("deploy.sh", {"CI_COMMIT_MESSAGE": message})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("needs literal [deploy]", result.stderr)
        result = self.run_script("deploy.sh", {"CI_COMMIT_MESSAGE": "Release demo [deploy]"})
        self.assertIn("Hosting is not enabled", result.stderr)

    def test_hosting_rejects_an_unprotected_branch(self):
        result = self.run_script("build.sh", {
            "HOSTING_ENABLED": "true", "CI_PROJECT_DIR": str(ROOT),
            "CI_COMMIT_SHA": "a" * 40, "CI_PIPELINE_ID": "1",
            "CI_DEFAULT_BRANCH": "main", "CI_COMMIT_BRANCH": "main",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Use a protected branch", result.stderr)

    def test_hosting_rejects_a_different_branch(self):
        result = self.run_script("build.sh", {
            "HOSTING_ENABLED": "true", "CI_PROJECT_DIR": str(ROOT),
            "CI_COMMIT_SHA": "a" * 40, "CI_PIPELINE_ID": "1",
            "CI_DEFAULT_BRANCH": "main", "CI_COMMIT_BRANCH": "feature",
            "CI_COMMIT_REF_PROTECTED": "true",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Use the default branch", result.stderr)

    def test_sync_rejects_an_unapproved_source(self):
        result = self.run_script("sync.sh", {
            "SYNC_ENABLED": "true", "GITHUB_REPO_URL": "file:///some/repository",
            "GITHUB_BRANCH": "main", "GITLAB_SYNC_TOKEN": "fake-test-token",
            "CI_PROJECT_URL": "https://gitlab.example.test/gemi/demo",
            "CI_DEFAULT_BRANCH": "main", "CI_COMMIT_BRANCH": "main",
            "CI_COMMIT_REF_PROTECTED": "true", "CI_PIPELINE_SOURCE": "web",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Use a public https://github.com", result.stderr)
        self.assertNotIn("fake-test-token", result.stdout + result.stderr)

    def test_sync_history_cases(self):
        for history in ("same", "fast-forward", "diverged"):
            with self.subTest(history=history), tempfile.TemporaryDirectory() as directory:
                mock_directory = Path(directory)
                mock = mock_directory / "git"
                mock.write_text('''#!/usr/bin/env bash
set -eu
# Ignore the credential.helper option before recognizing the requested operation.
if [[ "${1:-}" == -c ]]; then shift 2; fi
case "$1" in
  check-ref-format) exit 0 ;;
  init) mkdir -p "$3" ;;
  fetch)
    if [[ "$3" == https://github.com/* && -n "${GITLAB_SYNC_TOKEN:-}" ]]; then
      echo "GitLab token was passed to GitHub" >&2; exit 1
    fi ;;
  rev-parse)
    if [[ "$2" == refs/remotes/gitlab/source || "$MOCK_HISTORY" == same ]]; then
      printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n'
    else printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\n'; fi ;;
  merge-base) [[ "$MOCK_HISTORY" != diverged ]] ;;
  push) printf 'PUSHED %s\\n' "$3" ;;
  *) echo "Unexpected Git operation" >&2; exit 1 ;;
esac
''', encoding="utf-8", newline="\n")
                mock.chmod(0o700)
                result = self.run_script("sync.sh", {
                    "SYNC_ENABLED": "true", "MOCK_HISTORY": history,
                    "GITHUB_REPO_URL": "https://github.com/example/demo.git",
                    "GITHUB_BRANCH": "main", "GITLAB_SYNC_TOKEN": "fake-test-token",
                    "CI_PROJECT_URL": "https://gitlab.example.test/gemi/demo",
                    "CI_DEFAULT_BRANCH": "main", "CI_COMMIT_BRANCH": "main",
                    "CI_COMMIT_REF_PROTECTED": "true", "CI_PIPELINE_SOURCE": "web",
                }, mock_directory)
                self.assertNotIn("fake-test-token", result.stdout + result.stderr)
                if history == "diverged":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("histories diverged", result.stderr)
                    self.assertNotIn("PUSHED", result.stdout)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if history == "same":
                        self.assertNotIn("PUSHED", result.stdout)
                    else:
                        self.assertIn("PUSHED " + "b" * 40 + ":refs/heads/main", result.stdout)


if __name__ == "__main__":
    unittest.main()
