"""Creator canvas drops go to the poster or a key depending on the mode."""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_creator_drop_routing():
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "drop_routing_tests"
        subprocess.run(
            ["swiftc", "-sdk", sdk, "-parse-as-library",
             str(ROOT / "Model" / "CreatorDropRouting.swift"),
             str(ROOT / "tests" / "swift" / "CreatorDropRoutingTests.swift"),
             "-o", str(binary)],
            check=True,
        )
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        print(result.stdout)
        assert result.returncode == 0, result.stdout


if __name__ == "__main__":
    test_creator_drop_routing()
    print("ok")
