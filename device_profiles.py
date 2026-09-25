#!/usr/bin/env python3
"""Per-iPhone storage shared by the macOS app, the backend and the CLI.

Layout under ~/Library/Application Support/FaceLift/:

    devices.json                         index of known iPhones
    Devices/<udid>/profile.json          that iPhone's cards
    Devices/<udid>/skins/<hash>.png      artwork shown for each card
    Devices/<udid>/originals/<hash>/     raw artwork captured before FaceLift
                                         first changed the card
    Devices/<udid>/history/<hash>/       artwork FaceLift has written
    Legacy/                              pre-profile cards.json and skins/
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SUPPORT_ROOT = Path.home() / "Library" / "Application Support" / "FaceLift"

UDID_RE = re.compile(r"^[A-Za-z0-9-]{16,80}$")
CARD_HASH_RE = re.compile(r"^[-A-Za-z0-9_+=]{16,64}$")

# Leaves FaceLift overwrites when flashing a card, in display preference order.
ORIGINAL_LEAVES = (
    "cardBackgroundCombined@3x.png",
    "cardBackgroundCombined@2x.png",
    "cardBackgroundCombined.pdf",
)
HISTORY_LIMIT = 30


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def valid_udid(udid: str) -> bool:
    return bool(UDID_RE.fullmatch(udid or ""))


def valid_card(card_hash: str) -> bool:
    return bool(CARD_HASH_RE.fullmatch(card_hash or ""))


def _require(udid: str, card_hash: str | None = None) -> None:
    if not valid_udid(udid):
        raise ValueError("Invalid device identifier")
    if card_hash is not None and not valid_card(card_hash):
        raise ValueError("Invalid card identifier")


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def _read_json(path: Path, default):
    try:
        return json.loads(path.read_text("utf-8"))
    except (OSError, ValueError):
        return default


# MARK: - Paths

def device_dir(udid: str) -> Path:
    _require(udid)
    return SUPPORT_ROOT / "Devices" / udid


def profile_path(udid: str) -> Path:
    return device_dir(udid) / "profile.json"


def skin_path(udid: str, card_hash: str) -> Path:
    _require(udid, card_hash)
    return device_dir(udid) / "skins" / f"{card_hash}.png"


def original_dir(udid: str, card_hash: str) -> Path:
    _require(udid, card_hash)
    return device_dir(udid) / "originals" / card_hash


def history_dir(udid: str, card_hash: str) -> Path:
    _require(udid, card_hash)
    return device_dir(udid) / "history" / card_hash


def legacy_dir() -> Path:
    return SUPPORT_ROOT / "Legacy"


# MARK: - Profiles

def load_profile(udid: str) -> dict:
    data = _read_json(profile_path(udid), None)
    if not isinstance(data, dict) or not isinstance(data.get("cards"), list):
        return {"schema": 1, "udid": udid, "cards": []}
    return data


def profile_card_ids(udid: str) -> list[str]:
    ids: list[str] = []
    for entry in load_profile(udid).get("cards", []):
        card_id = entry.get("id") if isinstance(entry, dict) else None
        if isinstance(card_id, str) and card_id not in ids:
            ids.append(card_id)
    return ids


def card_in_profile(udid: str, card_hash: str) -> bool:
    return valid_udid(udid) and valid_card(card_hash) and card_hash in profile_card_ids(udid)


def save_profile_cards(udid: str, card_ids: list[str], source: str = "manual") -> None:
    """Replaces the card list, keeping metadata of cards that stay."""
    profile = load_profile(udid)
    known = {
        entry["id"]: entry
        for entry in profile.get("cards", [])
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }
    cards = []
    for card_id in dict.fromkeys(card_ids):
        if not valid_card(card_id):
            continue
        cards.append(known.get(card_id) or {"id": card_id, "addedAt": now_iso(), "source": source})
    profile.update({"schema": 1, "udid": udid, "cards": cards})
    write_json(profile_path(udid), profile)


# MARK: - Legacy store

def migrate_legacy_store() -> bool:
    """Moves the pre-profile cards.json and skins/ into Legacy/ once.

    Their owner is unknown, so they are never assigned to a device here.
    """
    moved = False
    legacy = legacy_dir()
    for name in ("cards.json", "skins"):
        source = SUPPORT_ROOT / name
        target = legacy / name
        if source.exists() and not target.exists():
            legacy.mkdir(parents=True, exist_ok=True)
            shutil.move(os.fspath(source), os.fspath(target))
            moved = True
    return moved


def legacy_card_ids() -> list[str]:
    data = _read_json(legacy_dir() / "cards.json", [])
    return [h for h in dict.fromkeys(data) if isinstance(h, str) and valid_card(h)] if isinstance(data, list) else []


# MARK: - Original artwork

def original_manifest(udid: str, card_hash: str) -> dict | None:
    data = _read_json(original_dir(udid, card_hash) / "manifest.json", None)
    return data if isinstance(data, dict) and isinstance(data.get("leaves"), dict) else None


def store_original(udid: str, card_hash: str, payloads: dict[str, bytes | None]) -> dict:
    """Saves the untouched artwork. An existing capture is never replaced."""
    existing = original_manifest(udid, card_hash)
    if existing is not None:
        return existing
    directory = original_dir(udid, card_hash)
    directory.mkdir(parents=True, exist_ok=True)
    leaves = {}
    for leaf in ORIGINAL_LEAVES:
        payload = payloads.get(leaf)
        if payload:
            (directory / leaf).write_bytes(payload)
            leaves[leaf] = {"present": True, "sha256": hashlib.sha256(payload).hexdigest(), "size": len(payload)}
        else:
            leaves[leaf] = {"present": False}
    png3 = payloads.get(ORIGINAL_LEAVES[0])
    png2 = payloads.get(ORIGINAL_LEAVES[1])
    manifest = {
        "schema": 1,
        "capturedAt": now_iso(),
        "leaves": leaves,
        # FaceLift writes the same PNG to @3x and @2x; Wallet ships two sizes.
        "suspectModified": bool(png3 and png2 and png3 == png2),
    }
    write_json(directory / "manifest.json", manifest)
    if load_current(udid, card_hash) is None:
        # Right after capture, the original is what the iPhone shows.
        set_current(udid, card_hash, "original")
    return manifest


def original_payloads(udid: str, card_hash: str) -> dict[str, bytes | None]:
    manifest = original_manifest(udid, card_hash)
    if manifest is None:
        raise FileNotFoundError("No original artwork captured for this card")
    directory = original_dir(udid, card_hash)
    payloads: dict[str, bytes | None] = {}
    for leaf in ORIGINAL_LEAVES:
        info = manifest["leaves"].get(leaf) or {}
        if not info.get("present"):
            payloads[leaf] = None
            continue
        data = (directory / leaf).read_bytes()
        if hashlib.sha256(data).hexdigest() != info.get("sha256"):
            raise ValueError(f"Original artwork {leaf} is damaged")
        payloads[leaf] = data
    return payloads


# MARK: - History

def load_history(udid: str, card_hash: str) -> list[dict]:
    data = _read_json(history_dir(udid, card_hash) / "history.json", [])
    return [e for e in data if isinstance(e, dict) and isinstance(e.get("file"), str)] if isinstance(data, list) else []


def record_history(udid: str, card_hash: str, image: bytes) -> dict:
    """Keeps a copy of artwork just written to the iPhone, newest first."""
    directory = history_dir(udid, card_hash)
    directory.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(image).hexdigest()
    name = f"{digest[:16]}.png"
    target = directory / name
    if not target.is_file():
        target.write_bytes(image)
    entries = [e for e in load_history(udid, card_hash) if e.get("sha256") != digest]
    entry = {"file": name, "sha256": digest, "appliedAt": now_iso()}
    entries.insert(0, entry)
    for stale in entries[HISTORY_LIMIT:]:
        try:
            (directory / Path(stale["file"]).name).unlink()
        except OSError:
            pass
    write_json(directory / "history.json", entries[:HISTORY_LIMIT])
    set_current(udid, card_hash, "custom", digest)
    return entry


# MARK: - Current artwork

def load_current(udid: str, card_hash: str) -> dict | None:
    """The artwork FaceLift last put on the iPhone for this card.

    FaceLift cannot see the phone's live state, so this only reflects its
    own writes: the original after capture or restore, else the last flash.
    """
    data = _read_json(history_dir(udid, card_hash) / "current.json", None)
    return data if isinstance(data, dict) and data.get("kind") in ("original", "custom") else None


def set_current(udid: str, card_hash: str, kind: str, sha256: str | None = None) -> None:
    entry = {"kind": kind, "at": now_iso()}
    if sha256:
        entry["sha256"] = sha256
    write_json(history_dir(udid, card_hash) / "current.json", entry)
