import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch

import apply_card_skin
import device_profiles
import facelift
import facelift_backend

UDID_A = "00008140-000A1B2C3D4E5F6A"
UDID_B = "00008150-000B1B2C3D4E5F6B"
CARD_A = "M6nDwZrkYbFlsodLgCbvyFZQ1cX="
CARD_B = "kJL-D0rr-SZhbj2c8nK-OQ9hCMX="


class SupportRootCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        self.support = self.home / "Library" / "Application Support" / "FaceLift"
        self.legacy = [self.home / ".facelift_cards.json", self.home / ".aircard_cards.json"]
        self._patches = [
            patch.object(device_profiles, "SUPPORT_ROOT", self.support),
            patch.object(facelift, "LEGACY_STORE_PATHS", self.legacy),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self) -> None:
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def run_backend(self, function, *args):
        output = io.StringIO()
        with redirect_stdout(output):
            result = function(*args)
        lines = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
        return result, lines


class ProfileStoreTests(SupportRootCase):
    def test_cards_are_kept_per_device(self) -> None:
        facelift.save_cards(UDID_A, [CARD_A, CARD_A])
        facelift.save_cards(UDID_B, [CARD_B])
        self.assertEqual(facelift.load_saved_cards(UDID_A), [CARD_A])
        self.assertEqual(facelift.load_saved_cards(UDID_B), [CARD_B])
        self.assertTrue(device_profiles.card_in_profile(UDID_A, CARD_A))
        self.assertFalse(device_profiles.card_in_profile(UDID_B, CARD_A))

    def test_saving_keeps_metadata_of_remaining_cards(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A], source="scan")
        device_profiles.save_profile_cards(UDID_A, [CARD_A, CARD_B])
        cards = {c["id"]: c for c in device_profiles.load_profile(UDID_A)["cards"]}
        self.assertEqual(cards[CARD_A]["source"], "scan")
        self.assertEqual(cards[CARD_B]["source"], "manual")

    def test_invalid_identifiers_never_become_paths(self) -> None:
        for udid in ("../../etc", "short", ""):
            with self.assertRaises(ValueError):
                device_profiles.device_dir(udid)
        with self.assertRaises(ValueError):
            device_profiles.skin_path(UDID_A, "../x")
        self.assertFalse(device_profiles.card_in_profile("../../etc", CARD_A))

    def test_global_store_moves_to_legacy_and_is_not_assigned(self) -> None:
        self.support.mkdir(parents=True)
        (self.support / "cards.json").write_text(json.dumps([CARD_A]))
        (self.support / "skins").mkdir()
        (self.support / "skins" / f"{CARD_A}.png").write_bytes(b"png")
        self.legacy[0].write_text(json.dumps([CARD_B]))

        self.assertEqual(facelift.load_saved_cards(UDID_A), [])
        self.assertFalse((self.support / "cards.json").exists())
        self.assertTrue((self.support / "Legacy" / "skins" / f"{CARD_A}.png").exists())
        self.assertEqual(device_profiles.legacy_card_ids(), [CARD_A, CARD_B])
        self.assertTrue(self.legacy[0].with_name(self.legacy[0].name + ".migrated").exists())

    def test_legacy_move_runs_once(self) -> None:
        self.support.mkdir(parents=True)
        (self.support / "cards.json").write_text(json.dumps([CARD_A]))
        self.assertTrue(device_profiles.migrate_legacy_store())
        (self.support / "cards.json").write_text(json.dumps(["stale"]))
        self.assertFalse(device_profiles.migrate_legacy_store())
        self.assertEqual(device_profiles.legacy_card_ids(), [CARD_A])


class OriginalAndHistoryTests(SupportRootCase):
    def test_original_is_captured_once(self) -> None:
        first = device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-2"})
        self.assertEqual(device_profiles.original_manifest(UDID_A, CARD_A), first)
        payloads = device_profiles.original_payloads(UDID_A, CARD_A)
        self.assertEqual(payloads["cardBackgroundCombined.pdf"], b"%PDF-1")
        self.assertIsNone(payloads["cardBackgroundCombined@3x.png"])
        self.assertFalse(first["suspectModified"])

    def test_identical_pngs_are_flagged_as_already_modified(self) -> None:
        manifest = device_profiles.store_original(UDID_A, CARD_A, {
            "cardBackgroundCombined@3x.png": b"\x89PNGsame",
            "cardBackgroundCombined@2x.png": b"\x89PNGsame",
        })
        self.assertTrue(manifest["suspectModified"])

    def test_damaged_original_is_refused(self) -> None:
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        (device_profiles.original_dir(UDID_A, CARD_A) / "cardBackgroundCombined.pdf").write_bytes(b"x")
        with self.assertRaises(ValueError):
            device_profiles.original_payloads(UDID_A, CARD_A)

    def test_history_is_newest_first_deduplicated_and_capped(self) -> None:
        device_profiles.record_history(UDID_A, CARD_A, b"one")
        device_profiles.record_history(UDID_A, CARD_A, b"two")
        device_profiles.record_history(UDID_A, CARD_A, b"one")
        entries = device_profiles.load_history(UDID_A, CARD_A)
        self.assertEqual(len(entries), 2)
        directory = device_profiles.history_dir(UDID_A, CARD_A)
        self.assertEqual((directory / entries[0]["file"]).read_bytes(), b"one")

        with patch.object(device_profiles, "HISTORY_LIMIT", 3):
            for index in range(5):
                device_profiles.record_history(UDID_A, CARD_A, f"img{index}".encode())
            entries = device_profiles.load_history(UDID_A, CARD_A)
        self.assertEqual(len(entries), 3)
        self.assertEqual(len(list(directory.glob("*.png"))), 3)


class CurrentArtworkTests(SupportRootCase):
    def test_original_is_current_after_capture(self) -> None:
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        self.assertEqual(device_profiles.load_current(UDID_A, CARD_A)["kind"], "original")

    def test_flash_makes_the_written_design_current(self) -> None:
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        entry = device_profiles.record_history(UDID_A, CARD_A, b"one")
        device_profiles.record_history(UDID_A, CARD_A, b"two")
        device_profiles.record_history(UDID_A, CARD_A, b"one")
        current = device_profiles.load_current(UDID_A, CARD_A)
        self.assertEqual((current["kind"], current["sha256"]), ("custom", entry["sha256"]))

    def test_recapture_does_not_reset_current(self) -> None:
        device_profiles.record_history(UDID_A, CARD_A, b"one")
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        self.assertEqual(device_profiles.load_current(UDID_A, CARD_A)["kind"], "custom")


class BackendGuardTests(SupportRootCase):
    def test_flash_refuses_a_card_of_another_device(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        device_profiles.save_profile_cards(UDID_B, [CARD_B])
        batch = Mock(return_value=True)
        with patch.object(facelift_backend, "write_files_batch", batch), \
             patch.object(facelift_backend, "write_file", batch):
            ok, lines = self.run_backend(facelift_backend.cmd_flash, UDID_B, CARD_A, "/nonexistent.png")
        self.assertFalse(ok)
        self.assertEqual(lines[-1]["reason"], "card_not_in_profile")
        batch.assert_not_called()

    def test_flash_requires_a_saved_original(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        batch = Mock(return_value=True)
        with patch.object(facelift_backend, "write_files_batch", batch):
            ok, lines = self.run_backend(facelift_backend.cmd_flash, UDID_A, CARD_A, "/nonexistent.png")
        self.assertFalse(ok)
        self.assertEqual(lines[-1]["reason"], "no_original")
        batch.assert_not_called()

    def test_successful_flash_is_recorded_in_history(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-1"})
        image = self.home / "new.png"
        image.write_bytes(b"\x89PNGnew")
        with patch.object(facelift_backend, "build_card_assets", return_value=(("a", b"1"),)), \
             patch.object(facelift_backend, "write_files_batch", Mock(return_value=True)):
            ok, _ = self.run_backend(facelift_backend.cmd_flash, UDID_A, CARD_A, str(image))
        self.assertTrue(ok)
        entries = device_profiles.load_history(UDID_A, CARD_A)
        self.assertEqual(len(entries), 1)

    def test_pull_only_writes_into_the_devices_own_folder(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        read = Mock(side_effect=AssertionError("device used"))
        with patch.object(facelift_backend, "read_card_artwork", read):
            ok, lines = self.run_backend(
                facelift_backend.cmd_pull_card, UDID_A, CARD_A,
                str(device_profiles.skin_path(UDID_B, CARD_A)),
            )
        self.assertFalse(ok)
        self.assertEqual(lines[-1]["reason"], "destination")

    def test_snapshot_captures_originals_and_shows_the_best_one(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        dest = device_profiles.skin_path(UDID_A, CARD_A)
        reader = Mock(return_value={
            "cardBackgroundCombined@3x.png": b"\x89PNG3x",
            "cardBackgroundCombined@2x.png": b"\x89PNG2x",
            "cardBackgroundCombined.pdf": None,
        })
        with patch.object(facelift_backend, "read_card_originals", reader):
            ok, lines = self.run_backend(facelift_backend.cmd_snapshot_card, UDID_A, CARD_A, str(dest))
            ok_again, _ = self.run_backend(facelift_backend.cmd_snapshot_card, UDID_A, CARD_A, str(dest))
        self.assertTrue(ok and ok_again)
        self.assertEqual(reader.call_count, 1)
        self.assertEqual(lines[-1]["asset"], "cardBackgroundCombined@3x.png")
        self.assertEqual(dest.read_bytes(), b"\x89PNG3x")
        self.assertFalse(lines[-1]["suspectModified"])

    def test_snapshot_without_destination_leaves_shown_artwork_alone(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        dest = device_profiles.skin_path(UDID_A, CARD_A)
        dest.parent.mkdir(parents=True)
        dest.write_bytes(b"new design")
        reader = Mock(return_value={"cardBackgroundCombined@3x.png": b"\x89PNG3x"})
        with patch.object(facelift_backend, "read_card_originals", reader):
            ok, lines = self.run_backend(facelift_backend.cmd_snapshot_card, UDID_A, CARD_A, None)
        self.assertTrue(ok)
        self.assertEqual(dest.read_bytes(), b"new design")
        self.assertIsNotNone(device_profiles.original_manifest(UDID_A, CARD_A))

    def test_snapshot_sync_failure_saves_nothing(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        reader = Mock(side_effect=apply_card_skin.CardReadSyncError("sync"))
        with patch.object(facelift_backend, "read_card_originals", reader):
            ok, lines = self.run_backend(
                facelift_backend.cmd_snapshot_card, UDID_A, CARD_A,
                str(device_profiles.skin_path(UDID_A, CARD_A)),
            )
        self.assertFalse(ok)
        self.assertEqual(lines[-1]["reason"], "sync")
        self.assertIsNone(device_profiles.original_manifest(UDID_A, CARD_A))

    def test_restore_writes_original_leaves_and_removes_added_ones(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        device_profiles.store_original(UDID_A, CARD_A, {"cardBackgroundCombined.pdf": b"%PDF-orig"})
        batch = Mock(return_value=True)
        remove = Mock(return_value=True)
        with patch.object(facelift_backend, "write_files_batch", batch), \
             patch.object(facelift_backend, "remove_pass_file", remove), \
             patch.object(facelift_backend, "native", Mock(return_value={})):
            ok, lines = self.run_backend(facelift_backend.cmd_restore_original, UDID_A, CARD_A)
        self.assertTrue(ok)
        pkpass = f"/var/mobile/Library/Passes/Cards/{CARD_A}.pkpass"
        batch.assert_any_call(UDID_A, pkpass, [("cardBackgroundCombined.pdf", b"%PDF-orig")])
        self.assertEqual(
            sorted(call.args[2] for call in remove.call_args_list),
            ["cardBackgroundCombined@2x.png", "cardBackgroundCombined@3x.png"],
        )
        self.assertEqual(lines[-1]["written"], ["cardBackgroundCombined.pdf"])
        self.assertEqual(device_profiles.load_current(UDID_A, CARD_A)["kind"], "original")

    def test_restore_without_original_does_nothing(self) -> None:
        device_profiles.save_profile_cards(UDID_A, [CARD_A])
        batch = Mock(return_value=True)
        with patch.object(facelift_backend, "write_files_batch", batch):
            ok, lines = self.run_backend(facelift_backend.cmd_restore_original, UDID_A, CARD_A)
        self.assertFalse(ok)
        self.assertEqual(lines[-1]["reason"], "no_original")
        batch.assert_not_called()


class DeviceSelectionTests(unittest.TestCase):
    DEVICES = [
        {"udid": UDID_A, "product": "iPhone17,1", "name": "A", "connection": "usb"},
        {"udid": UDID_B, "product": "iPhone16,2", "name": "B", "connection": "usb"},
    ]

    def test_preferred_device_stays_selected(self) -> None:
        with patch.object(facelift, "list_devices", return_value=self.DEVICES):
            self.assertEqual(facelift.get_connected_device()["udid"], UDID_A)
            chosen = facelift.get_connected_device(prefer=UDID_B)
        self.assertEqual(chosen["udid"], UDID_B)
        self.assertEqual([d["udid"] for d in chosen["available"]], [UDID_A, UDID_B])

    def test_missing_preferred_device_falls_back(self) -> None:
        with patch.object(facelift, "list_devices", return_value=self.DEVICES[1:]):
            self.assertEqual(facelift.get_connected_device(prefer=UDID_A)["udid"], UDID_B)


class RemovePassFileTests(unittest.TestCase):
    def test_remove_takes_the_file_out_without_writing_it_back(self) -> None:
        borrow = Mock(return_value=b"\x89PNG")
        with patch.object(apply_card_skin, "_borrow_pass_file", borrow):
            self.assertTrue(apply_card_skin.remove_pass_file(UDID_A, CARD_A, "cardBackgroundCombined@3x.png"))
        self.assertEqual(borrow.call_args.kwargs, {"restore": False})

    def test_write_back_is_skipped_when_not_restoring(self) -> None:
        def fake_native(command, udid, *args):
            if command == "pull":
                Path(args[1]).write_bytes(b"\x89PNG")
            return {"exitCode": 0, "targetGatePassed": True, "operation": {"ok": True}}

        write = Mock(return_value=True)
        with patch.object(apply_card_skin, "native", side_effect=fake_native), \
             patch.object(apply_card_skin, "run_json", Mock(return_value={"exitCode": 0, "ok": True})), \
             patch.object(apply_card_skin, "write_file", write):
            taken = apply_card_skin._borrow_pass_file(
                UDID_A, f"/var/mobile/Library/Passes/Cards/{CARD_A}.pkpass/x.png", restore=False
            )
        self.assertEqual(taken, b"\x89PNG")
        write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
