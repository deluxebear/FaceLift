#!/usr/bin/env python3
"""
FaceLift — Apple Wallet Card Skinner (via airlift exploit).
Customizes Apple Pay and Wallet card skins without a jailbreak.
"""

from __future__ import annotations

import io
import json
import os
import posixpath
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

# Ensure bundled and standard bin paths are in PATH
script_dir = Path(__file__).resolve().parent
for bin_path in [
    str(script_dir / "bin"),
    "/Applications/FaceLift.app/Contents/Resources/bin",
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin"
]:
    if os.path.isdir(bin_path) and bin_path not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{bin_path}:{os.environ.get('PATH', '')}"

import device_profiles
from apply_card_skin import (
    native,
    operation_ok,
    write_file,
    ROOT,
    DEVICE_HELPER,
)

TARGET_ASSETS = [
    "cardBackgroundCombined@3x.png",
    "cardBackgroundCombined@2x.png",
]

CACHE_FILES = ["FrontFace", "Preview"]

# Cards are stored per iPhone (see device_profiles.py). The pre-profile
# cards.json and the dotfiles below are only moved into Legacy/, never
# assigned to a device without asking.
LEGACY_STORE_PATHS = [
    Path.home() / ".facelift_cards.json",
    Path.home() / ".aircard_cards.json",
    Path.home() / ".lumicards_cards.json",
]

CARD_REGEXES = [
    re.compile(r"/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,44})(?:\.pkpass|\.cache|\.pkcache|/|\s|\"|\'|\)|,|$)"),
    re.compile(r"/([-A-Za-z0-9_+=]{20,44})\.(?:pkpass|cache|pkcache)"),
    re.compile(r"(?<![A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{27}=)(?![A-Za-z0-9+/_-])"),
]


def prepare_store() -> None:
    """Moves every pre-profile card list into Legacy/cards.json."""
    device_profiles.migrate_legacy_store()
    found = migrate_legacy_cards()
    if found:
        merged = list(dict.fromkeys(device_profiles.legacy_card_ids() + found))
        device_profiles.write_json(device_profiles.legacy_dir() / "cards.json", merged)


def load_saved_cards(udid: str) -> list[str]:
    """Loads the card hashes saved for one iPhone."""
    prepare_store()
    return device_profiles.profile_card_ids(udid)


def migrate_legacy_cards() -> list[str]:
    """Collects hashes from legacy dotfiles and renames them to *.migrated."""
    found: list[str] = []
    for store in LEGACY_STORE_PATHS:
        if not store.is_file():
            continue
        try:
            data = json.loads(store.read_text("utf-8"))
            if isinstance(data, list):
                found.extend(h for h in data if isinstance(h, str) and h not in found)
        except Exception:
            pass
        try:
            store.rename(store.with_name(store.name + ".migrated"))
        except OSError:
            pass
    return found


def save_cards(udid: str, cards: list[str], source: str = "manual") -> None:
    """Saves unique card hashes for one iPhone."""
    device_profiles.save_profile_cards(udid, cards, source)


def find_device_helper() -> str | None:
    """Finds the bundled device helper, the app's only device-communication tool."""
    root = Path(__file__).resolve().parent
    candidates = [root / "bin" / "device_helper", root / "build" / "device_helper"]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def list_devices() -> list[dict]:
    """Enumerates paired devices reachable over USB.

    Wi-Fi-paired devices can appear here too, and an entry whose session could
    not be opened is reported with an empty `product`.
    """
    helper = find_device_helper()
    if not helper:
        return []
    try:
        output = subprocess.check_output(
            [helper, "list"], text=True, stderr=subprocess.DEVNULL, timeout=30
        )
    except (OSError, subprocess.SubprocessError):
        return []

    for line in reversed(output.splitlines()):
        try:
            devices = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(devices, list):
            return [d for d in devices if isinstance(d, dict)]
    return []


def get_connected_device(prefer: str | None = None) -> dict | None:
    """Picks the connected iPhone out of the enumerated devices.

    `prefer` keeps the choice on the iPhone already in use while it stays
    connected, so two connected phones never swap on each poll.
    """
    usable = [d for d in list_devices() if d.get("udid") and d.get("product")]
    if not usable:
        return None
    # Enumeration order is not stable, and iPads can appear alongside the
    # iPhone. When the same phone is reachable over both Wi-Fi and USB,
    # prefer the wired transport — some services (AFC artwork reads) only
    # work there.
    iphones = [d for d in usable if str(d["product"]).startswith("iPhone")]
    pool = iphones or usable
    preferred = [d for d in pool if prefer and d["udid"] == prefer]
    if preferred:
        pool = preferred
    device = next((d for d in pool if d.get("connection") == "usb"), pool[0])

    return {
        "udid": device["udid"],
        "name": device.get("name") or "iPhone",
        "version": device.get("version") or "Unknown",
        "product": device["product"],
        "connection": device.get("connection") or "unknown",
        "available": [
            {
                "udid": d["udid"],
                "name": d.get("name") or "iPhone",
                "product": d["product"],
                "connection": d.get("connection") or "unknown",
            }
            for d in iphones or usable
        ],
    }


def syslog_command(udid: str) -> list[str] | None:
    """Builds the command that streams the device log, or None if unbundled."""
    helper = find_device_helper()
    if not helper:
        return None
    return [helper, "syslog", udid]


def capture_card_hashes(udid: str, existing_cards: list[str] | None = None) -> list[str]:
    """Listens to syslog and collects card hashes while the user opens Apple Wallet."""
    print("\n" + "=" * 60)
    print("📡 CARD SCANNING MODE")
    print("=" * 60)
    print("To detect your cards:")
    print("  👉 1) Double-click Side (Power) button to open Apple Pay.")
    print("  👉 2) Authenticate with Face ID.")
    print("  👉 3) Tap your card to trigger instant detection!")
    print("Press ENTER when finished.")
    print("=" * 60 + "\n")

    cmd = syslog_command(udid)
    if not cmd:
        print("\u274c Bundled device_helper is missing \u2014 cannot read the device log.")
        return list(existing_cards or [])
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    found_hashes = set(existing_cards or [])
    initial_count = len(found_hashes)

    try:
        import select

        while True:
            rlist, _, _ = select.select([sys.stdin, process.stdout], [], [], 0.2)
            if sys.stdin in rlist:
                sys.stdin.readline()
                break

            if process.stdout in rlist:
                line = process.stdout.readline()
                if not line:
                    break

                lower = line.lower()
                is_wallet = (
                    "passd" in lower
                    or "passbook" in lower
                    or "passkit" in lower
                    or "stockholm" in lower
                    or "nanopassd" in lower
                    or "wallet" in lower
                    or "/cards/" in lower
                )
                if not is_wallet:
                    continue

                is_ctx = any(
                    w in lower
                    for w in [
                        "card",
                        "pass",
                        "payment",
                        "pkpass",
                        "uniqueid",
                        "identifier",
                        "face",
                        "cache",
                        "stockholm",
                        "/cards/",
                    ]
                )
                if not is_ctx:
                    continue

                for r in CARD_REGEXES:
                    m = r.search(line)
                    if m:
                        h = m.group(1).strip().strip("'\"").rstrip(".").rstrip(",")
                        if len(h) == 36 and "-" in h:
                            continue
                        if h in [
                            "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
                            "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
                            "hwAtAmHKYwsQrJbT5cTNDsaxVME=",
                        ]:
                            continue
                        if h and h not in found_hashes:
                            found_hashes.add(h)
                            print(f"  ✨ Detected card [{len(found_hashes)}]: {h}")

    except KeyboardInterrupt:
        pass
    finally:
        process.terminate()
        process.wait()

    res = list(dict.fromkeys([*(existing_cards or []), *found_hashes]))
    save_cards(udid, res, source="scan")
    return res


def prepare_card_image(input_path: str) -> bytes:
    """Scales image to Apple Wallet standard (1536x969 PNG)."""
    clean_path = input_path.strip().strip("'").strip('"')
    path = Path(clean_path).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"File not found: {path}")

    try:
        from PIL import Image, ImageOps
        with Image.open(path) as img:
            img = img.convert("RGBA")
            target_size = (1536, 969)
            fitted = ImageOps.fit(img, target_size, method=Image.Resampling.LANCZOS)
            out_io = io.BytesIO()
            fitted.save(out_io, format="PNG")
            return out_io.getvalue()
    except Exception:
        pass

    # Fallback to macOS sips
    temp_out = f"/tmp/facelift_sips_{os.getpid()}.png"
    try:
        subprocess.check_call([
            "/usr/bin/sips",
            "-s", "format", "png",
            "-z", "969", "1536",
            str(path),
            "--out", temp_out
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data = Path(temp_out).read_bytes()
        Path(temp_out).unlink(missing_ok=True)
        return data
    except Exception as e:
        raise RuntimeError(f"Failed to process image: {e}")


def main():
    print("=" * 60)
    print("🎴 FaceLift — Apple Wallet Card Skinner (via airlift)")
    print("=" * 60)

    # 1. Device discovery
    print("\n[1/5] Searching for connected device...")
    device = get_connected_device()
    if not device:
        print("❌ iPhone not found! Connect your iPhone via USB and unlock the screen.")
        sys.exit(1)

    print(f"✅ Found: {device['name']} ({device['product']}, iOS {device['version']})")
    print(f"   UDID: {device['udid']}")

    # 2. Check airlift compatibility
    probe = native("probe", device["udid"])
    if not operation_ok(probe):
        print("❌ Airlift pre-check failed. Ensure the device is paired and trusted.")
        sys.exit(1)

    # 3. Card discovery / selection
    saved_cards = load_saved_cards(device["udid"])
    legacy = [h for h in device_profiles.legacy_card_ids() if h not in saved_cards]
    if legacy and not saved_cards:
        answer = input(
            f"\nFound {len(legacy)} card(s) saved by an older FaceLift. "
            f"Do they belong to {device['name']}? [y/N]: "
        ).strip().lower()
        if answer == "y":
            saved_cards = legacy
            save_cards(device["udid"], saved_cards, source="legacy")
    print(f"\n[2/5] Saved cards for {device['name']}: {len(saved_cards)}")
    for idx, h in enumerate(saved_cards, 1):
        print(f"  [{idx}] {h}")

    print("\nChoose an action:")
    print("  1 - Use existing cards")
    print("  2 - Scan cards (open Wallet & tap card)")
    print("  3 - Enter card hash(es) manually")
    mode = input("Your choice [1]: ").strip()

    hashes = saved_cards
    if mode == "2":
        hashes = capture_card_hashes(device["udid"], saved_cards)
    elif mode == "3":
        manual = input("Enter card hashes separated by commas or spaces: ").strip()
        new_items = [x.strip() for x in re.split(r"[\s,;]+", manual) if len(x.strip()) >= 16]
        for item in new_items:
            if item not in hashes:
                hashes.append(item)
        save_cards(device["udid"], hashes)

    if not hashes:
        print("❌ No cards available to flash.")
        sys.exit(1)

    print(f"\n[3/5] Ready to flash cards ({len(hashes)}):")
    for i, h in enumerate(hashes, 1):
        print(f"  [{i}] {h}")

    print("\nSelect cards to customize:")
    print("  'all' - apply to all cards")
    print("  comma-separated numbers (e.g. 1,3)")
    choice = input("Your choice [all]: ").strip().lower()

    if choice == "" or choice == "all":
        selected_hashes = hashes
    else:
        try:
            indices = [int(x.strip()) for x in choice.split(",") if x.strip()]
            selected_hashes = [hashes[i - 1] for i in indices if 1 <= i <= len(hashes)]
        except Exception:
            print("Invalid input. Applying to all cards.")
            selected_hashes = hashes

    if not selected_hashes:
        print("❌ No cards selected.")
        sys.exit(1)

    # 4. Prepare image
    print(f"\n[4/5] Preparing image...")
    while True:
        img_input = input("Drag and drop image file into terminal (or enter path): ").strip()
        try:
            png_bytes = prepare_card_image(img_input)
            print(f"✅ Image optimized for Apple Wallet ({len(png_bytes)} bytes)")
            break
        except Exception as e:
            print(f"❌ Error: {e}. Please specify another image.")

    # 5. Flash cards
    print(f"\n[5/5] Flashing skin to selected cards ({len(selected_hashes)})...")

    for idx, h in enumerate(selected_hashes, 1):
        print(f"\n--- [{idx}/{len(selected_hashes)}] Card: {h} ---")
        pkpass_dir = f"/var/mobile/Library/Passes/Cards/{h}.pkpass"

        for asset in TARGET_ASSETS:
            ok = write_file(device["udid"], pkpass_dir, asset, png_bytes)
            status = "OK" if ok else "FAIL"
            print(f"  -> {asset}: {status}")

        for ext in [".cache", ".pkcache"]:
            cache_dir = f"/var/mobile/Library/Passes/Cards/{h}{ext}"
            for leaf in CACHE_FILES:
                write_file(device["udid"], cache_dir, leaf, b"corrupted")
        print("  -> System cache cleared (.cache & .pkcache)")

    print("\n" + "=" * 60)
    print("🎉 DONE! All selected cards successfully updated!")
    print("=" * 60)
    print("1. Force close Apple Wallet on your iPhone.")
    print("2. If the image does not update immediately, restart your iPhone.")
    print("=" * 60)


if __name__ == "__main__":
    main()
