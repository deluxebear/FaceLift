import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import facelift


class CardStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        home = Path(self._tmp.name)
        self.store = home / "Library" / "Application Support" / "FaceLift" / "cards.json"
        self.legacy = [home / ".facelift_cards.json", home / ".aircard_cards.json"]
        self._patches = [
            patch.object(facelift, "CARDS_STORE_PATH", self.store),
            patch.object(facelift, "LEGACY_STORE_PATHS", self.legacy),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self) -> None:
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def test_save_creates_application_support_store(self) -> None:
        facelift.save_cards(["a", "b", "a"])
        self.assertEqual(json.loads(self.store.read_text()), ["a", "b"])

    def test_legacy_files_migrate_once_and_are_retired(self) -> None:
        self.legacy[0].write_text(json.dumps(["a", "b"]))
        self.legacy[1].write_text(json.dumps(["b", "c"]))

        self.assertEqual(facelift.load_saved_cards(), ["a", "b", "c"])
        self.assertEqual(json.loads(self.store.read_text()), ["a", "b", "c"])
        for path in self.legacy:
            self.assertFalse(path.exists())
            self.assertTrue(path.with_name(path.name + ".migrated").exists())

    def test_existing_store_ignores_legacy_files(self) -> None:
        facelift.save_cards([])
        self.legacy[0].write_text(json.dumps(["stale"]))
        self.assertEqual(facelift.load_saved_cards(), [])
        self.assertTrue(self.legacy[0].exists())


if __name__ == "__main__":
    unittest.main()
