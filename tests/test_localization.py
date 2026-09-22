"""Interface catalogs stay in sync with the strings the app looks up."""

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "FaceLiftApp.swift"
CATALOGS = {
    "en": ROOT / "Resources" / "en.lproj" / "Localizable.strings",
    "zh-Hans": ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings",
}
SPEC = re.compile(r"%(?:\d+\$)?[@dDuUxXfFeEgG]")


def load_catalog(path: Path) -> dict:
    raw = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)])
    data = json.loads(raw)
    assert isinstance(data, dict)
    return data


def unescape(literal: str) -> str:
    return (
        literal.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )


def specifiers(text: str) -> list:
    return [match.group(0) for match in SPEC.finditer(text) if match.group(0) != "%%"]


def lookup_keys(source: str) -> set:
    keys = set()
    for match in re.finditer(r'\b(?:L|LM|setStatus|log)\(\s*"((?:\\.|[^"\\])*)"', source):
        keys.add(unescape(match.group(1)))
    for enum_name in ("PasscodeLanguageTarget", "PasscodeBoldTarget"):
        body = re.search(rf"enum {enum_name}:.*?var id: String", source, re.S)
        assert body, enum_name
        keys.update(re.findall(r'=\s*"((?:\\.|[^"\\])*)"', body.group(0)))
    return keys


def test_catalogs_match_and_cover_the_interface():
    catalogs = {code: load_catalog(path) for code, path in CATALOGS.items()}
    assert set(catalogs["en"]) == set(catalogs["zh-Hans"])
    assert catalogs["en"]
    for key, english in catalogs["en"].items():
        assert english == key
        chinese = catalogs["zh-Hans"][key]
        assert chinese.strip()
        assert len(specifiers(key)) == len(specifiers(chinese))
        if key != chinese:
            assert not chinese.isascii() or "%" in chinese or key in {
                "Twitter / X",
                "TelephonyUI-10 (iOS 18+)",
                "TelephonyUI-9 (iOS 16–17)",
                "TelephonyUI-8 (iOS 14–15)",
            }

    missing = sorted(lookup_keys(SWIFT.read_text()) - set(catalogs["en"]))
    assert missing == [], missing


if __name__ == "__main__":
    test_catalogs_match_and_cover_the_interface()
    print("ok")
