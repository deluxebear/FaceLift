import io
import json
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path

from facelift_backend import cmd_inspect_passthm


class PasscodeThemeInspectionTests(unittest.TestCase):
    def inspect(self, folders):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "theme.passthm"
            with zipfile.ZipFile(path, "w") as archive:
                for folder in folders:
                    archive.writestr(f"{folder}/en-1---white.png", b"image")
            output = io.StringIO()
            with redirect_stdout(output):
                cmd_inspect_passthm(str(path))
            return json.loads(output.getvalue())

    def test_multi_version_archive_reports_all_versions_and_prefers_newest(self):
        result = self.inspect(["TelephonyUI-9", "TelephonyUI-10"])

        self.assertTrue(result["ok"])
        self.assertEqual(result["detected_version"], "TelephonyUI-10")
        self.assertEqual(result["supported_versions"], ["TelephonyUI-10", "TelephonyUI-9"])

    def test_single_version_archive_keeps_its_target(self):
        result = self.inspect(["TelephonyUI-8"])

        self.assertTrue(result["ok"])
        self.assertEqual(result["detected_version"], "TelephonyUI-8")
        self.assertEqual(result["supported_versions"], ["TelephonyUI-8"])


if __name__ == "__main__":
    unittest.main()
