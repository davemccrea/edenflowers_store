"""Run with Ansible's Python: python -m unittest discover -s infra/tests."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from jinja2 import Environment, StrictUndefined


TEMPLATE = Path(__file__).parents[1] / "roles/common/templates/backup.sh.j2"


class BackupTest(unittest.TestCase):
    def run_backup(self, failed_command="", host="production"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backups = root / "backups"
            backups.mkdir()
            (backups / "old.dump").write_text("previous good dump")
            photos = root / "photos"
            photos.mkdir()
            (photos / "flower.jpg").write_bytes(b"original photo")
            calls = root / "calls"
            env = Environment(undefined=StrictUndefined)
            env.filters["quote"] = shlex.quote
            script = env.from_string(TEMPLATE.read_text()).render(
                project_name="backup_test",
                db_name="shop_prod",
                inventory_hostname=host,
                vault_backup_storage_user="account",
                vault_backup_storage_host="box.example",
                vault_backup_storage_host_key="ssh-ed25519 example",
                vault_backup_heartbeat_url="https://heartbeat.example/secret",
            ).replace("/opt/backup_test/backups", str(backups)).replace(
                "/opt/backup_test/images/uploads", str(photos)
            )
            script_path = root / "backup.sh"
            script_path.write_text(script)
            subprocess.run(["sh", "-n", str(script_path)], check=True)
            subprocess.run(["shellcheck", str(script_path)], check=True)
            for command in ("pg_dump", "mv", "find", "rsync", "curl"):
                mock = root / command
                mock.write_text(
                    '#!/bin/sh\n'
                    'command=${0##*/}\n'
                    'echo "$command $*" >> "$CALLS"\n'
                    'stage=$command\n'
                    'if [ "$command" = rsync ]; then\n'
                    '  for arg do destination=$arg; done\n'
                    '  case "$destination" in\n'
                    '    */photos/) stage=photos_rsync ;;\n'
                    '  esac\n'
                    'fi\n'
                    '[ "$stage" != "$FAILED_COMMAND" ] || exit 1\n'
                    'case "$command" in\n'
                    '  pg_dump) echo dump ;;\n'
                    '  mv) /bin/mv "$@" ;;\n'
                    'esac\n'
                )
                mock.chmod(0o755)
            result = subprocess.run(
                ["sh", str(script_path)],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "CALLS": str(calls), "FAILED_COMMAND": failed_command},
                capture_output=True,
            )
            self.assertEqual((backups / "old.dump").read_text(), "previous good dump")
            return result.returncode, calls.read_text().splitlines(), list(backups.glob("*.tmp"))

    def test_success_pings_only_after_transfer(self):
        code, calls, partials = self.run_backup()
        self.assertEqual(code, 0)
        self.assertEqual([line.split()[0] for line in calls],
                         ["pg_dump", "mv", "find", "rsync", "rsync", "curl"])
        self.assertIn("--delete --exclude=*.tmp", calls[3])
        self.assertIn("StrictHostKeyChecking=yes", calls[3])
        self.assertTrue(calls[3].endswith("account@box.example:edenflowers/database/"))
        self.assertTrue(calls[4].endswith("account@box.example:edenflowers/photos/"))
        self.assertIn("/photos/ account@", calls[4])
        self.assertIn("--delete", calls[4])
        self.assertIn("StrictHostKeyChecking=yes", calls[4])
        self.assertNotIn("--exclude", calls[4])
        self.assertEqual(partials, [])

    def test_failures_stop_the_chain(self):
        stages = ["pg_dump", "mv", "find", "rsync", "photos_rsync", "curl"]
        commands = ["pg_dump", "mv", "find", "rsync", "rsync", "curl"]
        for index, command in enumerate(stages):
            with self.subTest(command=command):
                code, calls, _ = self.run_backup(command)
                self.assertNotEqual(code, 0)
                self.assertEqual([line.split()[0] for line in calls], commands[:index + 1])

    def test_real_mirrors_keep_sibling_backups_and_require_photo_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backups = root / "backups"
            photos = root / "photos"
            remote = root / "remote"
            for path in (backups, photos, remote / "database", remote / "photos"):
                path.mkdir(parents=True)
            (photos / "flower.jpg").write_bytes(b"original photo")
            (backups / "incomplete.dump.tmp").write_text("partial")
            (remote / "database/stale.dump").write_text("expired")
            (remote / "photos/deleted.jpg").write_text("deleted locally")
            (remote / "legacy.dump").write_text("preserve until migration verified")
            heartbeat = root / "heartbeat"
            for name, body in (("pg_dump", "echo dump"),
                               ("curl", f"touch {shlex.quote(str(heartbeat))}")):
                executable = root / name
                executable.write_text(f"#!/bin/sh\n{body}\n")
                executable.chmod(0o755)
            env = Environment(undefined=StrictUndefined)
            env.filters["quote"] = shlex.quote
            script = env.from_string(TEMPLATE.read_text()).render(
                project_name="backup_test", db_name="shop_prod",
                inventory_hostname="production",
                vault_backup_storage_user="account",
                vault_backup_storage_host="box.example",
                vault_backup_heartbeat_url="https://heartbeat.example/secret",
            ).replace("/opt/backup_test/backups", str(backups)).replace(
                "/opt/backup_test/images/uploads", str(photos)
            ).replace("account@box.example:edenflowers/", f"{remote}/")
            process_env = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}"}
            result = subprocess.run(["sh", "-c", script], env=process_env,
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(heartbeat.exists())
            self.assertEqual((remote / "photos/flower.jpg").read_bytes(), b"original photo")
            self.assertTrue(list((remote / "database").glob("shop_prod_*.dump")))
            self.assertFalse((remote / "database/incomplete.dump.tmp").exists())
            self.assertFalse((remote / "database/stale.dump").exists())
            self.assertFalse((remote / "photos/deleted.jpg").exists())
            self.assertTrue((remote / "legacy.dump").exists())

            heartbeat.unlink()
            (photos / "flower.jpg").unlink()
            photos.rmdir()
            result = subprocess.run(["sh", "-c", script], env=process_env,
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(heartbeat.exists())
            self.assertTrue((remote / "photos/flower.jpg").exists())

    def test_nonproduction_has_no_transfer_or_heartbeat(self):
        code, calls, _ = self.run_backup(host="staging")
        self.assertEqual(code, 0)
        self.assertEqual([line.split()[0] for line in calls], ["pg_dump", "mv", "find"])


if __name__ == "__main__":
    unittest.main()
