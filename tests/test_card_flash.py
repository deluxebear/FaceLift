import base64
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch

import device_profiles
import facelift_backend
import apply_card_skin


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


UDID = "00008140-000A1B2C3D4E5F6A"
CARD = "M6nDwZrkYbFlsodLgCbvyFZQ1cX="


class CardFlashTests(unittest.TestCase):
    def setUp(self) -> None:
        self._support = tempfile.TemporaryDirectory()
        self._patch = patch.object(device_profiles, "SUPPORT_ROOT", Path(self._support.name))
        self._patch.start()
        device_profiles.save_profile_cards(UDID, [CARD])
        device_profiles.store_original(UDID, CARD, {"cardBackgroundCombined.pdf": b"%PDF-original"})

    def tearDown(self) -> None:
        self._patch.stop()
        self._support.cleanup()

    def test_cache_removal_moves_link_and_required_companion_payload(self) -> None:
        successful = {
            "exitCode": 0,
            "targetGatePassed": True,
            "operation": {"ok": True},
        }
        with (
            patch.object(apply_card_skin, "native", return_value=successful),
            patch.object(apply_card_skin, "run_json", return_value={"exitCode": 0, "ok": True}) as transfer,
        ):
            result = apply_card_skin.remove_files(
                "device", "/protected/card.cache", ["FrontFace"], retries=1
            )

        self.assertTrue(result)
        command = transfer.call_args.args[0]
        self.assertEqual(len(command), 6)
        self.assertIn("/airlift-link-", command[4])
        self.assertTrue(command[5].endswith("/removed-0"))

    def test_flash_writes_pdf_and_removes_rendered_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image_path = Path(temporary) / "card.png"
            image_path.write_bytes(PNG_1X1)
            write_file = Mock(return_value=True)
            remove_files = Mock(return_value=True)

            with (
                patch.object(facelift_backend, "write_file", write_file),
                patch.object(facelift_backend, "write_files_batch", Mock(return_value=False)),
                patch.object(facelift_backend, "remove_files", remove_files),
                redirect_stdout(io.StringIO()),
            ):
                result = facelift_backend.cmd_flash(UDID, CARD, str(image_path))

        self.assertTrue(result)

        writes = [call.args for call in write_file.call_args_list]
        pass_assets = {
            leaf: payload
            for _, target, leaf, payload in writes
            if target.endswith(".pkpass")
        }
        self.assertEqual(
            set(pass_assets),
            {
                "cardBackgroundCombined@3x.png",
                "cardBackgroundCombined@2x.png",
                "cardBackgroundCombined.pdf",
            },
        )
        self.assertTrue(pass_assets["cardBackgroundCombined.pdf"].startswith(b"%PDF-"))

        removals = [call.args for call in remove_files.call_args_list]
        for extension in (".cache", ".pkcache"):
            self.assertIn((UDID, f"/var/mobile/Library/Passes/Cards/{CARD}{extension}", list(facelift_backend.CACHE_FILES)), removals)

    def test_flash_fails_when_wallet_cache_cannot_be_removed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image_path = Path(temporary) / "card.png"
            image_path.write_bytes(PNG_1X1)
            output = io.StringIO()
            with (
                patch.object(facelift_backend, "write_files_batch", return_value=True),
                patch.object(facelift_backend, "remove_files", side_effect=[True, False]),
                redirect_stdout(output),
            ):
                result = facelift_backend.cmd_flash(UDID, CARD, str(image_path))
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertFalse(result)
        self.assertEqual(messages[-1]["type"], "error")

    def test_flash_reports_failure_when_an_asset_write_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image_path = Path(temporary) / "card.png"
            image_path.write_bytes(PNG_1X1)
            write_file = Mock(
                side_effect=[True, True, False, True, True, True, True, True, True]
            )
            output = io.StringIO()

            with (
                patch.object(facelift_backend, "write_file", write_file),
                redirect_stdout(output),
            ):
                result = facelift_backend.cmd_flash(UDID, CARD, str(image_path))

        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertFalse(result)
        self.assertEqual(messages[-1]["type"], "error")
        self.assertFalse(any(message["type"] == "success" for message in messages))

    def test_flash_reports_failure_when_pdf_conversion_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image_path = Path(temporary) / "card.png"
            image_path.write_bytes(PNG_1X1)
            write_file = Mock(return_value=True)
            output = io.StringIO()

            with (
                patch.object(facelift_backend, "write_file", write_file),
                patch.object(
                    facelift_backend,
                    "build_card_assets",
                    side_effect=subprocess.CalledProcessError(1, ["sips"]),
                ),
                redirect_stdout(output),
            ):
                result = facelift_backend.cmd_flash(UDID, CARD, str(image_path))

        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertFalse(result)
        self.assertEqual(messages[-1]["type"], "error")
        write_file.assert_not_called()


class CardArtworkReadTests(unittest.TestCase):
    def test_prefers_the_combined_face_over_other_images(self) -> None:
        chosen = apply_card_skin.choose_card_artwork([
            "logo@3x.png",
            "strip@2x.png",
            "cardBackgroundCombined@2x.png",
            "cardBackgroundCombined@3x.png",
        ])
        self.assertEqual(chosen, "cardBackgroundCombined@3x.png")

    def test_skips_logos_and_keeps_a_background(self) -> None:
        chosen = apply_card_skin.choose_card_artwork([
            "logo.png",
            "icon@2x.png",
            "thumbnail.png",
            "background@2x.png",
        ])
        self.assertEqual(chosen, "background@2x.png")

    def test_pass_asset_id_points_at_the_cards_directory(self) -> None:
        asset = apply_card_skin.pass_asset_id(
            "/var/mobile/Library/Passes/Cards/abc=.pkpass/cardBackgroundCombined@3x.png"
        )
        self.assertEqual(
            asset,
            "../../../../../var/mobile/Library/Passes/Cards/abc=.pkpass/cardBackgroundCombined@3x.png",
        )
        with self.assertRaises(ValueError):
            apply_card_skin.pass_asset_id("/etc/passwd")

    def test_rejects_a_hash_before_touching_the_phone(self) -> None:
        with patch.object(apply_card_skin, "native", side_effect=AssertionError("device used")):
            self.assertIsNone(apply_card_skin.read_card_artwork("udid", "../etc", "/tmp/out.png"))

    def test_corrupt_cache_bytes_are_not_an_image(self) -> None:
        self.assertIsNone(apply_card_skin.image_payload(b"corrupted"))
        self.assertIsNotNone(apply_card_skin.image_payload(PNG_1X1))


if __name__ == "__main__":
    unittest.main()
