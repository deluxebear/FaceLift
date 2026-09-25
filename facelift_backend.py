#!/usr/bin/env python3
"""
Backend engine for FaceLift native macOS GUI app.
"""
from __future__ import annotations

import base64
import io
import json
import os
import re
import subprocess
import sys
import time
import zipfile
from pathlib import Path

# Augment PATH so bundled tools and system tools are always found
script_dir = Path(__file__).resolve().parent
bundled_bin = script_dir / "bin"
bundled_lib = script_dir / "lib"
app_bin = Path("/Applications/FaceLift.app/Contents/Resources/bin")
app_lib = Path("/Applications/FaceLift.app/Contents/Resources/lib")

paths_to_add = [
    str(bundled_bin),
    str(app_bin),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin"
]
for p in reversed(paths_to_add):
    if os.path.isdir(p) and p not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{p}:{os.environ.get('PATH', '')}"

lib_paths = [str(bundled_lib), str(app_lib)]
for lp in lib_paths:
    if os.path.isdir(lp):
        cur_dyld = os.environ.get("DYLD_LIBRARY_PATH", "")
        os.environ["DYLD_LIBRARY_PATH"] = f"{lp}:{cur_dyld}" if cur_dyld else lp

import device_profiles
from apply_card_skin import (
    native,
    operation_ok,
    read_card_artwork,
    read_card_originals,
    remove_pass_file,
    _write_preview,
    CardReadSyncError,
    clear_passcode_cache,
    write_file,
    write_files_batch,
    build_archive_multi,
    ROOT,
    DEVICE_HELPER,
)
from card_assets import CACHE_FILES, build_card_assets
from facelift import (
    find_device_helper,
    get_connected_device,
    load_saved_cards,
    save_cards,
)


def cmd_device(prefer: str | None = None):
    if not find_device_helper():
        print(json.dumps({"connected": False, "error": "device_helper_missing"}))
        return
    device = get_connected_device(prefer)
    if not device:
        print(json.dumps({"connected": False, "error": "no_device"}))
        return
    probe = native("probe", device["udid"])
    device["airlift_compatible"] = operation_ok(probe)
    device["connected"] = True
    print(json.dumps(device))


def _card_not_in_profile(udid: str, card_hash: str) -> bool:
    """Refuses any card the iPhone's own profile does not list."""
    if device_profiles.card_in_profile(udid, card_hash):
        return False
    print(json.dumps({
        "ok": False,
        "type": "error",
        "card": card_hash,
        "reason": "card_not_in_profile",
        "message": "This card does not belong to the connected iPhone.",
    }))
    sys.stdout.flush()
    return True


def _skin_destination(udid: str, card_hash: str, dest_path: str) -> Path | None:
    """Artwork read from an iPhone may only land in that iPhone's folder."""
    try:
        expected = device_profiles.skin_path(udid, card_hash)
    except ValueError:
        return None
    dest = Path(dest_path).expanduser()
    return dest if dest.resolve(strict=False) == expected.resolve(strict=False) else None


def cmd_pull_card(udid: str, card_hash: str, dest_path: str) -> bool:
    if _card_not_in_profile(udid, card_hash):
        return False
    dest = _skin_destination(udid, card_hash, dest_path)
    if dest is None:
        print(json.dumps({"ok": False, "reason": "destination", "asset": "", "path": ""}))
        return False
    try:
        leaf = read_card_artwork(udid, card_hash, os.fspath(dest))
    except CardReadSyncError:
        print(json.dumps({"ok": False, "reason": "sync", "asset": "", "path": ""}))
        return False
    print(json.dumps({
        "ok": bool(leaf) and dest.is_file(),
        "reason": "" if leaf else "missing",
        "asset": leaf or "",
        "path": os.fspath(dest) if leaf else "",
    }))
    return bool(leaf)


def cmd_snapshot_card(udid: str, card_hash: str, dest_path: str | None = None) -> bool:
    """Captures the card's untouched artwork once.

    The capture is kept byte for byte under originals/ so it can be written
    back later; an existing capture is never replaced. With `dest_path`, a
    preview is also copied there for the app to show. Without it the shown
    artwork is left alone (used right before flashing a new design).
    """
    if _card_not_in_profile(udid, card_hash):
        return False
    dest = _skin_destination(udid, card_hash, dest_path) if dest_path else None
    if dest_path and dest is None:
        print(json.dumps({"ok": False, "reason": "destination", "asset": "", "path": ""}))
        return False
    manifest = device_profiles.original_manifest(udid, card_hash)
    if manifest is None:
        try:
            payloads = read_card_originals(udid, card_hash, device_profiles.ORIGINAL_LEAVES)
        except CardReadSyncError:
            print(json.dumps({"ok": False, "reason": "sync", "asset": "", "path": ""}))
            return False
        manifest = device_profiles.store_original(udid, card_hash, payloads)
    directory = device_profiles.original_dir(udid, card_hash)
    leaf = next(
        (name for name in device_profiles.ORIGINAL_LEAVES if manifest["leaves"].get(name, {}).get("present")),
        None,
    )
    preview = directory / "preview.png"
    if leaf and not preview.is_file():
        try:
            _write_preview((directory / leaf).read_bytes(), preview)
        except (OSError, subprocess.SubprocessError):
            pass
    if dest and leaf and preview.is_file():
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(preview.read_bytes())
    shown = bool(dest and leaf and dest.is_file())
    print(json.dumps({
        "ok": bool(leaf) and (dest is None or shown),
        "reason": "" if leaf else "missing",
        "asset": leaf or "",
        "path": os.fspath(dest) if shown else "",
        "captured": True,
        "suspectModified": bool(manifest.get("suspectModified")),
    }))
    return bool(leaf)


def _invalidate_card_cache(udid: str, card_hash: str) -> None:
    cache_leaves = [(leaf, b"corrupted") for leaf in CACHE_FILES]
    for ext in [".cache", ".pkcache"]:
        cache_dir = f"/var/mobile/Library/Passes/Cards/{card_hash}{ext}"
        try:
            ok_cache = write_files_batch(udid, cache_dir, cache_leaves)
        except Exception:
            ok_cache = False
        if not ok_cache:
            for leaf, payload in cache_leaves:
                try:
                    write_file(udid, cache_dir, leaf, payload)
                except Exception:
                    pass


def cmd_restore_original(udid: str, card_hash: str) -> bool:
    """Writes the captured original artwork back to the iPhone.

    Leaves the original pass had are written back byte for byte; leaves
    FaceLift added are taken out again.
    """
    if _card_not_in_profile(udid, card_hash):
        return False
    try:
        payloads = device_profiles.original_payloads(udid, card_hash)
    except (OSError, ValueError) as exc:
        print(json.dumps({"ok": False, "reason": "no_original", "error": str(exc)}))
        return False

    pkpass_dir = f"/var/mobile/Library/Passes/Cards/{card_hash}.pkpass"
    present = [(leaf, data) for leaf, data in payloads.items() if data]
    absent = [leaf for leaf, data in payloads.items() if not data]

    ok = True
    if present:
        try:
            ok = write_files_batch(udid, pkpass_dir, present)
        except (OSError, RuntimeError, subprocess.SubprocessError):
            ok = False
        if not ok:
            ok = all(write_file(udid, pkpass_dir, leaf, data) for leaf, data in present)
    if not ok:
        print(json.dumps({"ok": False, "reason": "write", "error": "Could not write original artwork"}))
        return False

    removed = []
    for leaf in absent:
        try:
            if remove_pass_file(udid, card_hash, leaf):
                removed.append(leaf)
        except CardReadSyncError as exc:
            print(json.dumps({"ok": False, "reason": "sync", "error": f"Could not remove {leaf}: {exc}"}))
            return False
    native("sweep", udid)
    _invalidate_card_cache(udid, card_hash)
    print(json.dumps({
        "ok": True,
        "written": [leaf for leaf, _ in present],
        "removed": removed,
    }))
    return True


def cmd_get_saved_cards(udid: str):
    print(json.dumps({"ok": True, "cards": load_saved_cards(udid)}))


def cmd_save_cards(udid: str, cards_json: str):
    try:
        cards = json.loads(cards_json)
        if isinstance(cards, list):
            save_cards(udid, [c for c in cards if isinstance(c, str)])
            print(json.dumps({"ok": True}))
            return
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return
    print(json.dumps({"ok": False, "error": "Invalid format"}))


def cmd_prepare_image(src: str, dst: str):
    path = Path(src).expanduser()
    if not path.is_file():
        print(json.dumps({"ok": False, "error": f"File not found: {src}"}))
        return
    try:
        from PIL import Image, ImageOps
        with Image.open(path) as img:
            img = img.convert("RGBA")
            target_size = (1536, 969)
            fitted = ImageOps.fit(img, target_size, method=Image.Resampling.LANCZOS)
            fitted.save(dst, format="PNG")
        print(json.dumps({"ok": True, "path": dst}))
        return
    except ImportError:
        pass
    except Exception as e:
        pass
    
    # Fallback to macOS built-in sips tool (built into every macOS, 0 dependencies!)
    try:
        import subprocess
        subprocess.check_call([
            "/usr/bin/sips",
            "-s", "format", "png",
            "-z", "969", "1536",
            str(path),
            "--out", str(dst)
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(json.dumps({"ok": True, "path": dst}))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))


def cmd_flash(udid: str, card_hash: str, image_path: str) -> bool:
    if _card_not_in_profile(udid, card_hash):
        return False
    if device_profiles.original_manifest(udid, card_hash) is None:
        print(json.dumps({
            "type": "error",
            "card": card_hash,
            "reason": "no_original",
            "message": "Original artwork has not been saved yet.",
        }))
        sys.stdout.flush()
        return False
    img_path = Path(image_path)
    if not img_path.is_file():
        print(json.dumps({"ok": False, "error": "Image file not found"}))
        return False

    image_bytes = img_path.read_bytes()
    try:
        asset_payloads = build_card_assets(image_bytes)
    except (OSError, subprocess.SubprocessError):
        print(json.dumps({
            "type": "error",
            "card": card_hash,
            "message": "Failed to prepare card artwork"
        }))
        sys.stdout.flush()
        return False

    pkpass_dir = f"/var/mobile/Library/Passes/Cards/{card_hash}.pkpass"
    
    total_steps = len(asset_payloads) + (len(CACHE_FILES) * 2) + 1
    step = 0
    all_ok = True

    step += 1
    print(json.dumps({
        "type": "progress",
        "card": card_hash,
        "step": step,
        "total": total_steps,
        "message": f"Writing {len(asset_payloads)} artwork files (fast batch)..."
    }))
    sys.stdout.flush()

    try:
        ok = write_files_batch(udid, pkpass_dir, asset_payloads)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        ok = False

    if not ok:
        # Fallback to individual writes if batch fails
        for asset, payload in asset_payloads:
            try:
                ok_single = write_file(udid, pkpass_dir, asset, payload)
            except Exception:
                ok_single = False
            if not ok_single:
                all_ok = False

    # Clear cache with batch
    cache_leaves = [(leaf, b"corrupted") for leaf in CACHE_FILES]
    for ext in [".cache", ".pkcache"]:
        cache_dir = f"/var/mobile/Library/Passes/Cards/{card_hash}{ext}"
        step += 1
        print(json.dumps({
            "type": "progress",
            "card": card_hash,
            "step": step,
            "total": total_steps,
            "message": f"Invalidating cache ({ext})..."
        }))
        sys.stdout.flush()
        try:
            ok_cache = write_files_batch(udid, cache_dir, cache_leaves)
        except Exception:
            ok_cache = False
        if not ok_cache:
            for leaf, payload in cache_leaves:
                try:
                    write_file(udid, cache_dir, leaf, payload)
                except Exception:
                    pass

    step += 1
    if not all_ok:
        print(json.dumps({
            "type": "error",
            "card": card_hash,
            "step": step,
            "total": total_steps,
            "message": f"Failed to update {card_hash[:12]}..."
        }))
        sys.stdout.flush()
        return False

    try:
        device_profiles.record_history(udid, card_hash, image_bytes)
    except OSError:
        pass

    print(json.dumps({
        "type": "success",
        "card": card_hash,
        "step": step,
        "total": total_steps,
        "message": f"Successfully updated {card_hash[:12]}..."
    }))
    sys.stdout.flush()
    return True


KEYPAD_SUBTEXTS = {
    "0": "+",
    "1": "",
    "2": "A B C",
    "3": "D E F",
    "4": "G H I",
    "5": "J K L",
    "6": "M N O",
    "7": "P Q R S",
    "8": "T U V",
    "9": "W X Y Z",
}

# Cyrillic keypad subtexts for Russian & Ukrainian locales
CYRILLIC_SUBTEXTS_RU = {
    "2": "А Б В Г",
    "3": "Д Е Ж З",
    "4": "И Й К Л",
    "5": "М Н О П",
    "6": "Р С Т У",
    "7": "Ф Х Ц Ч",
    "8": "Ш Щ Ъ Ы",
    "9": "Ь Э Ю Я",
}

CYRILLIC_SUBTEXTS_UK = {
    "2": "А Б В Г",
    "3": "Д Е Ж З",
    "4": "І Ї Й К",
    "5": "Л М Н О",
    "6": "П Р С Т",
    "7": "У Ф Х Ц",
    "8": "Ч Ш Щ Ь",
    "9": "Ю Я",
}


# System locales supported for TelephonyUI passcode keypad caches
KEYPAD_LOCALES = [
    "en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"
]


def parse_passthm_archive(
    passthm_path: str,
    telephony_ver: str = "TelephonyUI-10",
    target_lang: str = "all",
    target_bold: str = "both"
) -> list[tuple[str, str, bytes]]:
    path = Path(passthm_path).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"Passcode theme file not found: {passthm_path}")

    with zipfile.ZipFile(path, "r") as z:
        image_entries = [
            n for n in z.namelist()
            if not n.startswith("__MACOSX")
            and not n.endswith("/")
            and not Path(n).name.startswith(".")
            and any(n.lower().endswith(ext) for ext in (".png", ".jpg", ".jpeg"))
        ]
        if not image_entries:
            return []

        # Support universal (TelephonyUI-8 + 9 + 10) or specific folder
        norm_ver = (telephony_ver or "TelephonyUI-10").strip()
        if norm_ver.lower() in ("all", "universal"):
            target_dirs = [
                "/var/mobile/Library/Caches/TelephonyUI-10",
                "/var/mobile/Library/Caches/TelephonyUI-9",
                "/var/mobile/Library/Caches/TelephonyUI-8",
            ]
        else:
            target_dirs = [f"/var/mobile/Library/Caches/{norm_ver}"]

        items_dict: dict[str, bytes] = {}

        # Normalize target_lang & target_bold
        target_lang = (target_lang or "all").lower().strip()
        target_bold = (target_bold or "both").lower().strip()

        for entry in image_entries:
            leaf = Path(entry).name
            data = z.read(entry)

            stem = Path(leaf).stem
            stem_clean = re.sub(r"--?white(?:-bold)?$", "", stem, flags=re.IGNORECASE)
            m = re.search(r"^(?:([a-zA-Z]+)-)?([0-9*#])(?:-([^-\n]+))?", stem_clean)
            digit = None
            subtext = ""
            orig_lang = None
            if m:
                orig_lang = m.group(1)
                digit = m.group(2)
                if m.group(3):
                    subtext = m.group(3).strip()
            if not digit:
                m2 = re.search(r"([0-9*#])", leaf)
                if m2:
                    digit = m2.group(1)

            # Strip non-subtext keywords from subtext
            if subtext and subtext.lower() in ("bold", "regular", "white", "black", "light", "dark", "normal"):
                subtext = ""

            # If user requested universal (all + both), keep raw leaf
            if target_lang == "all" and target_bold == "both":
                items_dict[leaf] = data

            if digit:
                if target_lang == "all":
                    langs = list(KEYPAD_LOCALES)
                    if orig_lang and orig_lang.lower() not in langs:
                        langs.insert(0, orig_lang.lower())
                else:
                    # Put target_lang FIRST, other SECOND
                    langs = [target_lang]
                    if target_lang != "other":
                        langs.append("other")

                if target_bold == "bold":
                    bold_suffixes = ["-bold"]
                elif target_bold == "regular":
                    bold_suffixes = [""]
                else:
                    bold_suffixes = ["", "-bold"]

                std_subtext = KEYPAD_SUBTEXTS.get(digit)

                for lang in langs:
                    for bold_suffix in bold_suffixes:
                        # 1. Blank subtext variant (e.g. ru-5---white-bold.png)
                        items_dict[f"{lang}-{digit}---white{bold_suffix}.png"] = data

                        # 2. Standard Latin subtext (e.g. ru-5-J K L--white-bold.png)
                        if std_subtext:
                            items_dict[f"{lang}-{digit}-{std_subtext}--white{bold_suffix}.png"] = data
                            if " " in std_subtext:
                                items_dict[f"{lang}-{digit}-{std_subtext.replace(' ', '')}--white{bold_suffix}.png"] = data

                        # 3. Cyrillic subtexts for Russian & Ukrainian
                        if lang in ("ru", "all") and digit in CYRILLIC_SUBTEXTS_RU:
                            cyr_ru = CYRILLIC_SUBTEXTS_RU[digit]
                            items_dict[f"{lang}-{digit}-{cyr_ru}--white{bold_suffix}.png"] = data
                        if lang in ("uk", "all") and digit in CYRILLIC_SUBTEXTS_UK:
                            cyr_uk = CYRILLIC_SUBTEXTS_UK[digit]
                            items_dict[f"{lang}-{digit}-{cyr_uk}--white{bold_suffix}.png"] = data

                        # 4. Custom subtext variant if present in the source asset
                        if subtext:
                            items_dict[f"{lang}-{digit}-{subtext}--white{bold_suffix}.png"] = data

        res = []
        for tdir in target_dirs:
            for leaf, data in items_dict.items():
                res.append((tdir, leaf, data))
        return res


def cmd_inspect_passthm(passthm_path: str):
    path = Path(passthm_path).expanduser()
    if not path.is_file():
        print(json.dumps({"ok": False, "error": f"File not found: {passthm_path}"}))
        return
    try:
        with zipfile.ZipFile(path, "r") as z:
            entries = [entry.lower() for entry in z.namelist()]
            supported_versions = [
                f"TelephonyUI-{version}"
                for version in (10, 9, 8)
                if any(
                    f"telephonyui-{version}" in entry or f"telephony-{version}" in entry
                    for entry in entries
                )
            ]
        detected_ver = supported_versions[0] if supported_versions else "TelephonyUI-10"

        items = parse_passthm_archive(str(path), detected_ver)
        if not items:
            print(json.dumps({"ok": False, "error": "No image assets found in archive"}))
            return

        keys_preview = {}
        for _, leaf, data in items:
            m = re.search(r'^[a-zA-Z]+-([0-9*#])-?', leaf)
            digit = m.group(1) if m else None
            if not digit:
                m2 = re.search(r'([0-9*#])', leaf)
                if m2:
                    digit = m2.group(1)
            if digit and digit not in keys_preview:
                b64 = base64.b64encode(data).decode("utf-8")
                mime = "image/png" if leaf.lower().endswith(".png") else "image/jpeg"
                keys_preview[digit] = f"data:{mime};base64,{b64}"

        print(json.dumps({
            "ok": True,
            "name": path.stem,
            "detected_version": detected_ver,
            "supported_versions": supported_versions,
            "file_count": len(items),
            "keys_preview": keys_preview
        }))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))


def cmd_flash_passthm(
    udid: str,
    passthm_path: str,
    telephony_ver: str = "TelephonyUI-10",
    target_lang: str = "all",
    target_bold: str = "both"
) -> bool:
    path = Path(passthm_path).expanduser()
    if not path.is_file():
        print(json.dumps({"ok": False, "error": "Passcode theme file not found"}))
        return False

    try:
        items_to_write = parse_passthm_archive(str(path), telephony_ver, target_lang, target_bold)
        if not items_to_write:
            print(json.dumps({"ok": False, "error": "No image assets found in archive"}))
            return False

        # Group items by target directory (e.g. /var/mobile/Library/Caches/TelephonyUI-10)
        items_by_dir: dict[str, list[tuple[str, bytes]]] = {}
        for tdir, leaf, payload in items_to_write:
            items_by_dir.setdefault(tdir, []).append((leaf, payload))

        # Check for marker files like _big or _small in the theme package
        try:
            with zipfile.ZipFile(path, "r") as z:
                for entry in z.namelist():
                    leaf_name = Path(entry).name
                    if leaf_name in ("_big", "_small") and not entry.endswith("/"):
                        marker_data = z.read(entry)
                        for tdir in items_by_dir:
                            if not any(leaf == leaf_name for leaf, _ in items_by_dir[tdir]):
                                items_by_dir[tdir].append((leaf_name, marker_data))
        except Exception:
            pass

        total_steps = sum(len(f) for f in items_by_dir.values())
        processed_files = 0

        print(json.dumps({
            "type": "progress",
            "step": 0,
            "total": total_steps,
            "message": f"Flashing passcode theme '{path.stem}' ({total_steps} assets)..."
        }))
        sys.stdout.flush()

        for tdir, dir_files in items_by_dir.items():
            tdir_name = Path(tdir).name
            base_step = processed_files

            def make_progress_handler(base: int):
                def on_atc_progress(p: dict):
                    idx = p.get("index", 0)
                    leaf = p.get("leaf", "")
                    curr = min(base + idx, total_steps)
                    print(json.dumps({
                        "type": "progress",
                        "step": curr,
                        "total": total_steps,
                        "leaf": leaf,
                        "message": f"Writing {leaf} ({curr}/{total_steps})..."
                    }))
                    sys.stdout.flush()
                return on_atc_progress

            print(json.dumps({
                "type": "progress",
                "step": base_step,
                "total": total_steps,
                "message": f"Flashing {len(dir_files)} asset(s) into {tdir_name}..."
            }))
            sys.stdout.flush()

            ok = write_files_batch(
                udid,
                tdir,
                dir_files,
                retries=3,
                progress_callback=make_progress_handler(base_step),
            )

            if not ok:
                # If batch failed, fallback to file-by-file write for this directory
                print(json.dumps({
                    "type": "warning",
                    "message": f"Batch write notice for {tdir_name}, falling back to file-by-file write..."
                }))
                sys.stdout.flush()

                failed_leaves = []
                for f_idx, (leaf, payload) in enumerate(dir_files, 1):
                    curr = base_step + f_idx
                    print(json.dumps({
                        "type": "progress",
                        "step": curr,
                        "total": total_steps,
                        "leaf": leaf,
                        "message": f"[Fallback] Writing {leaf} ({curr}/{total_steps})..."
                    }))
                    sys.stdout.flush()

                    single_ok = write_file(udid, tdir, leaf, payload, retries=3)
                    if not single_ok:
                        failed_leaves.append(leaf)
                    time.sleep(0.08)

                if failed_leaves:
                    print(json.dumps({
                        "type": "error",
                        "message": f"Could not write {len(failed_leaves)} file(s) in {tdir_name}: {', '.join(failed_leaves[:5])}"
                    }))
                    sys.stdout.flush()
                    return False

            processed_files += len(dir_files)

        print(json.dumps({
            "type": "success",
            "step": total_steps,
            "total": total_steps,
            "message": f"Passcode theme '{path.stem}' successfully applied! Lock your iPhone to check."
        }))
        sys.stdout.flush()
        return True

    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return False


def cmd_restore_default_passcode(udid: str, version: str) -> bool:
    try:
        removed, backup_dir = clear_passcode_cache(udid, version)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return False
    print(json.dumps({"ok": True, "removed": removed, "backup": backup_dir}))
    return True


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No command provided"}))
        sys.exit(1)

    cmd = sys.argv[1]
    norm_cmd = cmd.lstrip("-")
    if norm_cmd == "device":
        prefer = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--prefer" else None
        cmd_device(prefer)
    elif norm_cmd == "cards" and len(sys.argv) > 2:
        cmd_get_saved_cards(sys.argv[2])
    elif norm_cmd == "save-cards" and len(sys.argv) > 3:
        cmd_save_cards(sys.argv[2], sys.argv[3])
    elif norm_cmd == "pull-card" and len(sys.argv) > 4:
        if not cmd_pull_card(sys.argv[2], sys.argv[3], sys.argv[4]):
            sys.exit(1)
    elif norm_cmd == "snapshot-card" and len(sys.argv) > 3:
        # Succeeds whenever the original is saved, even for a card that has
        # none of the artwork leaves; the JSON line says what was found.
        cmd_snapshot_card(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
        if not device_profiles.valid_udid(sys.argv[2]) or not device_profiles.valid_card(sys.argv[3]) \
                or device_profiles.original_manifest(sys.argv[2], sys.argv[3]) is None:
            sys.exit(1)
    elif norm_cmd == "restore-original" and len(sys.argv) > 3:
        if not cmd_restore_original(sys.argv[2], sys.argv[3]):
            sys.exit(1)
    elif norm_cmd == "prepare-image" and len(sys.argv) > 3:
        cmd_prepare_image(sys.argv[2], sys.argv[3])
    elif norm_cmd == "flash" and len(sys.argv) > 4:
        if not cmd_flash(sys.argv[2], sys.argv[3], sys.argv[4]):
            sys.exit(1)
    elif norm_cmd == "inspect-passthm" and len(sys.argv) > 2:
        cmd_inspect_passthm(sys.argv[2])
    elif norm_cmd == "flash-passthm" and len(sys.argv) > 3:
        t_ver = sys.argv[4] if len(sys.argv) > 4 else "TelephonyUI-10"
        t_lang = sys.argv[5] if len(sys.argv) > 5 else "all"
        t_bold = sys.argv[6] if len(sys.argv) > 6 else "both"
        if not cmd_flash_passthm(sys.argv[2], sys.argv[3], t_ver, t_lang, t_bold):
            sys.exit(1)
    elif norm_cmd == "restore-default-passcode" and len(sys.argv) > 3:
        if not cmd_restore_default_passcode(sys.argv[2], sys.argv[3]):
            sys.exit(1)
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
