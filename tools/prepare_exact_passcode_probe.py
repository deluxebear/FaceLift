"""Prepare ten 225-pixel keys matching the iOS 27 post-reboot cache layout."""

from io import BytesIO
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
POSTER = ROOT / "Resources" / "DefaultPasscodePoster.png"
OUTPUT = ROOT / "build" / "passcode-probe-225"
BUTTONS = (
    ("1", "", 0, 0),
    ("2", "A B C", 0, 1),
    ("3", "D E F", 0, 2),
    ("4", "G H I", 1, 0),
    ("5", "J K L", 1, 1),
    ("6", "M N O", 1, 2),
    ("7", "P Q R S", 2, 0),
    ("8", "T U V", 2, 1),
    ("9", "W X Y Z", 2, 2),
    ("0", "", 3, 1),
)


def prepare() -> dict[str, bytes]:
    with Image.open(POSTER) as source:
        if source.size != (915, 1148):
            raise ValueError(f"Unexpected poster dimensions: {source.size}")
        poster = source.convert("RGBA")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = {}
    for digit, letters, row, column in BUTTONS:
        left = column * 305 + 40
        top = row * 287 + 31
        key = poster.crop((left, top, left + 225, top + 225))
        name = f"other-{digit}-{letters}--white.png" if letters else f"other-{digit}---white.png"
        stream = BytesIO()
        key.save(stream, format="PNG")
        data = stream.getvalue()
        (OUTPUT / name).write_bytes(data)
        result[name] = data
    return result


if __name__ == "__main__":
    files = prepare()
    print(f"Prepared {len(files)} exact-cache-name 225×225 keys in {OUTPUT}")
