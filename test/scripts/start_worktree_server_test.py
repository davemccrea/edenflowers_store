import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/start-worktree-server.sh"


class WorktreeServerTest(unittest.TestCase):
    def test_waits_for_tidewave_and_reports_startup_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, body in {
                "wt": "exit 0",
                "curl": 'printf "%s\\n" "$@" > curl-args; exit "$CURL_EXIT"',
            }.items():
                executable = root / name
                executable.write_text(f"#!/bin/sh\n{body}\n")
                executable.chmod(0o755)

            for exit_code in (0, 7):
                with self.subTest(exit_code=exit_code):
                    result = subprocess.run(
                        ["bash", str(SCRIPT), "14998"],
                        cwd=root,
                        env={
                            **os.environ,
                            "PATH": f"{root}:{os.environ['PATH']}",
                            "CURL_EXIT": str(exit_code),
                        },
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 0 if exit_code == 0 else 1)
                    arguments = (root / "curl-args").read_text()
                    self.assertIn("http://localhost:14998/tidewave/mcp", arguments)
                    self.assertIn('"method":"initialize"', arguments)
                    self.assertIn("--retry-max-time\n60", arguments)
                    if exit_code:
                        self.assertIn("tmp/dev.log", result.stderr)


if __name__ == "__main__":
    unittest.main()
