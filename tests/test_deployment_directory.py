"""Check real deployment-directory creation and boundaries in Linux temp folders."""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


@unittest.skipUnless(os.name == "posix" and BASH, "Linux/POSIX and Bash are required")
class DeploymentDirectoryTests(unittest.TestCase):
    def prepare(self, root, target, checkout):
        environment = os.environ.copy()
        environment.update({"DEPLOY_ROOT": str(root), "DEPLOY_DIR": str(target),
                            "CI_PROJECT_DIR": str(checkout)})
        # This helper touches only the temporary fixture: no Docker, Git or server.
        return subprocess.run(
            [BASH, "-c", 'set -euo pipefail; source scripts/common.sh; prepare_deployment_directory'],
            cwd=ROOT, env=environment, capture_output=True, text=True, timeout=10,
        )

    def test_creates_app_directory_and_preserves_it_on_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root, checkout = base / "hosting", base / "checkout"
            root.mkdir(mode=0o750)
            checkout.mkdir()
            target = root / "team" / "demo"
            original_root_mode = stat.S_IMODE(root.stat().st_mode)
            result = self.prepare(root, target, checkout)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(target))
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), original_root_mode)
            # Existing content and deliberately chosen permissions survive retry.
            sentinel = target / "existing-data.txt"
            sentinel.write_text("preserve me", encoding="utf-8")
            target.chmod(0o750)
            result = self.prepare(root, target, checkout)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve me")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o750)

    def test_rejects_invalid_paths_before_creating_any_directory(self):
        cases = ("outside", "prefix-sibling", "root-itself", "relative-target",
                 "relative-root", "missing-root", "filesystem-root", "traversal",
                 "symlink-escape", "dangling-symlink-escape", "existing-file",
                 "checkout", "inside-checkout", "checkout-parent")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                root, checkout, outside = base / "hosting", base / "checkout", base / "outside"
                for folder in (root, checkout, outside):
                    folder.mkdir()
                target = root / "demo"
                if case == "outside": target = outside / "demo"
                elif case == "prefix-sibling": target = base / "hosting-other" / "demo"
                elif case == "root-itself": target = root
                elif case == "relative-target": target = "relative-demo"
                elif case == "relative-root": root = "relative-root"
                elif case == "missing-root": root, target = base / "missing", base / "missing" / "demo"
                elif case == "filesystem-root": root = Path("/")
                elif case == "traversal": target = root / ".." / "outside" / "demo"
                elif case in ("symlink-escape", "dangling-symlink-escape"):
                    destination = outside if case == "symlink-escape" else base / "missing-outside"
                    (root / "link").symlink_to(destination, target_is_directory=True)
                    target = root / "link" / "demo"
                elif case == "existing-file": target.write_text("keep this file", encoding="utf-8")
                elif case in ("checkout", "inside-checkout", "checkout-parent"):
                    checkout = root / "checkout" / "source"
                    checkout.mkdir(parents=True)
                    target = checkout if case == "checkout" else (
                        checkout / "demo" if case == "inside-checkout" else checkout.parent)
                before = sorted(str(path.relative_to(base)) for path in base.rglob("*"))
                result = self.prepare(root, target, checkout)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("ERROR:", result.stderr)
                self.assertEqual(sorted(str(path.relative_to(base)) for path in base.rglob("*")), before)

    @unittest.skipIf(getattr(os, "geteuid", lambda: -1)() == 0,
                     "Permission checks need an unprivileged test user")
    def test_reports_missing_runner_write_permission(self):
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                root, checkout = base / "hosting", base / "checkout"
                root.mkdir()
                checkout.mkdir()
                target = root / "demo"
                protected = target if existing else root
                if existing:
                    target.mkdir()
                protected.chmod(0o500)
                try:
                    result = self.prepare(root, target, checkout)
                    self.assertNotEqual(result.returncode, 0)
                    expected = "cannot write" if existing else "Cannot create DEPLOY_DIR"
                    self.assertIn(expected, result.stderr)
                    self.assertEqual(target.exists(), existing)
                    self.assertEqual(stat.S_IMODE(protected.stat().st_mode), 0o500)
                finally:
                    # Restore only this test fixture so TemporaryDirectory can remove it.
                    protected.chmod(0o700)

    def test_rejects_symlinked_release_files_without_changing_them(self):
        for name in ("compose.json", "release.txt"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                root, checkout = base / "hosting", base / "checkout"
                root.mkdir()
                checkout.mkdir()
                target = root / "demo"
                target.mkdir()
                outside = base / "unrelated.txt"
                outside.write_text("preserve me", encoding="utf-8")
                (target / name).symlink_to(outside)
                result = self.prepare(root, target, checkout)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Release files must not be symbolic links", result.stderr)
                self.assertTrue((target / name).is_symlink())
                self.assertEqual(outside.read_text(encoding="utf-8"), "preserve me")


if __name__ == "__main__":
    unittest.main()
