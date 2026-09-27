# Wallpaper metadata template

`WallpaperMetadata.mov` contains only two metadata tracks, no video or audio.
It is sourced from `templates/metadata.mov` in the MIT-licensed project
[tmfadhlul/apple-video-to-livephotos](https://github.com/tmfadhlul/apple-video-to-livephotos),
revision `d0c2bf897962762fde4f1e0a1ec78a7948ff0567`.

SHA-256: `d9aee0440214bfb0fad75cfe8cde11f098b4546a8ff9fff13807a63d12cff800`.
The upstream license is reproduced in [LICENSE](LICENSE), and both this notice
and the license are included in the application bundle.

FaceLift reads the constant 136-byte `live-photo-info` payload and its complete
format description, including private setup data. It writes one copy per output
frame beginning at 0.05 seconds. It generates its own UUID, still image marker
and identity transform; the template's cover time is not copied.

The payload is a compatibility template, not motion measurements of the user's
video. The user confirmed on 2026-09-27 that the regenerated sample plays in iPhone
Photos and once when waking the Lock Screen. This verifies that sample, not all
videos or iOS versions. macOS `PHLivePhoto` recognition is not a wallpaper
eligibility test.
