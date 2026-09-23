import io
import json
import plistlib
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

import apply_card_skin
import facelift_backend


DEVICE_ID = "00008130-001A123456789ABC"


def native_ok(operation=None):
    return {
        "exitCode": 0,
        "targetGatePassed": True,
        "operation": operation or {"ok": True},
    }


class PasscodeRestoreTests(unittest.TestCase):
    def test_moves_cache_out_backs_it_up_and_cleans_up(self):
        calls = []

        def fake_native(command, *args):
            calls.append(command)
            if command == "stage":
                with zipfile.ZipFile(args[4]) as archive:
                    self.assertEqual(
                        archive.read("p0/p1/p2/link"),
                        b"../../../var/mobile/Library/Caches",
                    )
                with open(args[5], "rb") as file:
                    rows = plistlib.load(file)["Books"]
                ids = [row["Persistent ID"] for row in rows]
                self.assertIn(
                    "../../../../../var/mobile/Library/Caches/TelephonyUI-10",
                    ids,
                )
                self.assertEqual(len(ids), 4)
            if command == "stat-media":
                return native_ok({"ok": True, "st_ifmt": "S_IFDIR"})
            return native_ok()

        def fake_run_json(command, timeout):
            if Path(command[0]).name == "airtraffic_host":
                calls.append("move-cache")
                self.assertEqual(len(command), 6)
                return {"exitCode": 0, "ok": True}
            if command[1] == "backup-passcode-cache":
                calls.append("backup")
                self.assertEqual(timeout, 600)
                return native_ok({"ok": True, "backedUp": 17})
            if command[1] == "finish-write":
                calls.append("finish-write")
                self.assertEqual(timeout, 600)
                return native_ok()
            self.fail(command)

        with (
            patch.object(apply_card_skin, "native", side_effect=fake_native),
            patch.object(apply_card_skin, "run_json", side_effect=fake_run_json),
        ):
            backed_up, backup = apply_card_skin.clear_passcode_cache(
                DEVICE_ID, "TelephonyUI-10"
            )

        self.assertEqual(backed_up, 17)
        self.assertIn("PasscodeCacheBackups", backup)
        self.assertEqual(calls[-1], "finish-write")
        self.assertEqual(calls.count("move-cache"), 1)
        self.assertEqual(calls.count("backup"), 1)

    def test_backup_failure_moves_original_cache_back(self):
        calls = []
        rolled_back = False

        def fake_native(command, *args):
            calls.append(command)
            if command == "stat-media":
                if rolled_back:
                    return native_ok({"ok": False})
                return native_ok({"ok": True, "st_ifmt": "S_IFDIR"})
            return native_ok()

        def fake_run_json(command, timeout):
            nonlocal rolled_back
            if Path(command[0]).name == "airtraffic_host":
                calls.append("move")
                if calls.count("move") == 2:
                    rolled_back = True
                return {"exitCode": 0, "ok": True}
            if command[1] == "backup-passcode-cache":
                return native_ok({"ok": False, "reason": "read cache file"})
            if command[1] == "finish-write":
                calls.append(("finish-write", command[5]))
                return native_ok()
            self.fail(command)

        with (
            patch.object(apply_card_skin, "native", side_effect=fake_native),
            patch.object(apply_card_skin, "run_json", side_effect=fake_run_json),
        ):
            with self.assertRaisesRegex(RuntimeError, "read cache file"):
                apply_card_skin.clear_passcode_cache(DEVICE_ID, "TelephonyUI-10")

        self.assertEqual(calls.count("move"), 2)
        self.assertEqual(len([item for item in calls if isinstance(item, tuple)]), 2)

    def test_sync_error_is_reported_and_cleanup_preserves_cache(self):
        calls = []

        def fake_native(command, *args):
            calls.append(command)
            if command == "stat-media":
                return native_ok({"ok": False})
            return native_ok()

        def fake_run_json(command, timeout):
            if Path(command[0]).name == "airtraffic_host":
                return {"exitCode": 5, "ok": False, "error": "expected assets absent from manifest"}
            if command[1] == "finish-write":
                calls.append("finish-write")
                return native_ok()
            self.fail(command)

        with (
            patch.object(apply_card_skin, "native", side_effect=fake_native),
            patch.object(apply_card_skin, "run_json", side_effect=fake_run_json),
        ):
            with self.assertRaisesRegex(RuntimeError, "expected assets absent from manifest"):
                apply_card_skin.clear_passcode_cache(DEVICE_ID, "TelephonyUI-10")

        self.assertEqual(calls[-1], "finish-write")

    def test_failed_rollback_preserves_relocated_cache(self):
        cleanup_names = []
        move_count = 0
        relocated_name = ""

        def fake_native(command, *args):
            if command == "stat-media":
                return native_ok({"ok": True, "st_ifmt": "S_IFDIR"})
            return native_ok()

        def fake_run_json(command, timeout):
            nonlocal move_count, relocated_name
            if Path(command[0]).name == "airtraffic_host":
                move_count += 1
                if move_count == 2:
                    relocated_name = command[4].split("/")[-1]
                return {"exitCode": 0, "ok": move_count == 1}
            if command[1] == "backup-passcode-cache":
                return native_ok({"ok": False, "reason": "read cache file"})
            if command[1] == "finish-write":
                cleanup_names.append(command[5])
                return native_ok()
            self.fail(command)

        with (
            patch.object(apply_card_skin, "native", side_effect=fake_native),
            patch.object(apply_card_skin, "run_json", side_effect=fake_run_json),
        ):
            with self.assertRaisesRegex(RuntimeError, "cache remains on iPhone"):
                apply_card_skin.clear_passcode_cache(DEVICE_ID, "TelephonyUI-10")

        self.assertEqual(move_count, 2)
        self.assertEqual(len(cleanup_names), 2)
        self.assertTrue(all(name != relocated_name for name in cleanup_names))

    def test_rejects_unknown_target_before_contacting_device(self):
        with patch.object(apply_card_skin, "native") as native:
            with self.assertRaises(ValueError):
                apply_card_skin.clear_passcode_cache(DEVICE_ID, "../../Passes")
            native.assert_not_called()

    def test_backend_reports_backup_location(self):
        output = io.StringIO()
        with (
            patch.object(
                facelift_backend, "clear_passcode_cache", return_value=(17, "/backup")
            ),
            redirect_stdout(output),
        ):
            self.assertTrue(
                facelift_backend.cmd_restore_default_passcode(
                    DEVICE_ID, "TelephonyUI-10"
                )
            )
        self.assertEqual(
            json.loads(output.getvalue()),
            {"ok": True, "removed": 17, "backup": "/backup"},
        )


if __name__ == "__main__":
    unittest.main()
