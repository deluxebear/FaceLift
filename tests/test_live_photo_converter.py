"""Exercise real AVFoundation encoding and PHLivePhoto validation without Photos writes."""

import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.skipif(sys.platform != "darwin", reason="AVFoundation and Photos require macOS")
def test_live_photo_converter():
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "live_photo_tests"
        subprocess.run(
            ["swiftc", "-sdk", sdk, "-parse-as-library",
             str(ROOT / "Model" / "VideoWallpaper.swift"),
             str(ROOT / "Model" / "LivePhotoConverter.swift"),
             str(ROOT / "tests" / "swift" / "LivePhotoConverterTests.swift"),
             "-o", str(binary)],
            check=True, capture_output=True, text=True,
        )
        result = subprocess.run([str(binary), str(ROOT / "Resources" / "LivePhoto" / "WallpaperMetadata.mov")], capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(sys.platform != "darwin", reason="AVFoundation and Photos require macOS")
def test_wallpaper_animation_dimensions():
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "wallpaper_dimension_tests"
        subprocess.run(
            ["swiftc", "-sdk", sdk, "-parse-as-library", "-D", "WALLPAPER_DIMENSION_TESTS",
             str(ROOT / "Model" / "VideoWallpaper.swift"),
             str(ROOT / "Model" / "LivePhotoConverter.swift"),
             str(ROOT / "tests" / "swift" / "LivePhotoConverterTests.swift"),
             str(ROOT / "Model" / "VideoWallpaperModel.swift"),
             str(ROOT / "tests" / "swift" / "WallpaperDimensionsTests.swift"),
             "-o", str(binary)],
            check=True, capture_output=True, text=True,
        )
        result = subprocess.run([str(binary), str(ROOT / "Resources" / "LivePhoto" / "WallpaperMetadata.mov")],
                                capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stdout + result.stderr


if __name__ == "__main__":
    test_live_photo_converter()
    test_wallpaper_animation_dimensions()
    print("ok")
