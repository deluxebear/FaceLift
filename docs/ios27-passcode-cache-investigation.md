# iOS 27 passcode cache reboot test

Device: iPhone 16 Pro (`iPhone17,1`), iOS 27.0 (`24A437`).

The generated Chinese numeral theme appeared on the lock screen immediately
after writing, but disappeared after a reboot and first unlock. Three write
layouts produced the same result:

| Write layout | Files | Image size | Before reboot | After reboot |
| --- | ---: | --- | --- | --- |
| Original all-language theme | ~950 | 305×287 | Visible | Default keypad |
| `zh` + `other`, regular + bold | 109 including `_big` | 305×287 | Visible | Default keypad |
| Exact names from regenerated cache | 10 | 225×225 | Visible | Default keypad |

After the second row's reboot, `restore-default-passcode` backed up the
`TelephonyUI-10` directory to the Mac before removing it from the phone. The
backup contained only ten system images named `other-0---white.png` through
`other-9-W X Y Z--white.png`, all 225×225. None matched the written theme
bytes. The phone was then rebooted to regenerate the default cache before the
third test.

This establishes that cache writes are temporary on this tested device.
Reducing the number of files and matching the regenerated cache's names and
dimensions did not make the theme survive reboot. The precise iOS process
that replaces the cache was subsequently identified, but the exact reason for
the cache miss is not yet confirmed. `tools/prepare_exact_passcode_probe.py`
prepares the ten-image comparison payload locally and does not write to a phone.

## Reboot log and one-key comparison

In the iOS 27.0 sysdiagnose, SpringBoard logged `clear legacy storage` at
18:18:24.925 and `deleting legacy storage at URL: <private>` at 18:18:24.942,
after reboot and before first unlock. Disassembly of the matching
`TelephonyUI.framework` build shows `TPFileStorageManager imageWithName:` calls
`clearLegacyStorageIfNecessary` when an image read returns nil; that routine
deletes versioned `TelephonyUI*` cache directories. This explains why the
custom images are absent after reboot, but it does not identify which missing
image or file property caused the read to return nil.

On 2026-09-23, one existing system image, `other-1---white.png`, was moved to
the Media area, backed up on the Mac, overwritten in place with the 225×225
gold `壹` PNG, and moved back. The AFC-reported `st_birthtime` remained
`1790158704940183708` before and after the overwrite, and readback matched
all 69,775 payload bytes. The original 1,880-byte PNG is backed up at
`~/Library/Application Support/FaceLift/PasscodeCacheBackups/00008140-000205DC0129801C/TelephonyUI-10/inplace-dbb0b23f0a2c8a3d9013/other-1---white.png`.
This tests whether preserving the original file identity/attributes changes
reboot behavior. The user confirmed that the gold `壹` was visible on the lock
screen immediately afterward. After reboot, the first passcode screen showed
the system default digit again. Thus an in-place write that preserves the
file's AFC-reported creation time does not make this cache customization
survive reboot on the tested iOS 27.0 device. We cannot assert that the file's
Data Protection class was preserved: AFC does not expose that attribute.

No persistent fix has been demonstrated via `TelephonyUI-10` cache writes.
Do not claim reboot persistence in the app, and do not automatically repeat
the same write variants. A durable on-device solution would require a
different, verified mechanism rather than another cache-size or filename
adjustment. The tested phone is back to the system default keypad.

## Supported-interface conclusion

Question asked: does iOS expose any supported interface that would make a
custom passcode-keypad theme survive reboot? Answer, based on the evidence
above and the framework architecture: no.

Why the cache path cannot persist by design. `TelephonyUI-10` lives under
`/var/mobile/Library/Caches/`, which iOS treats as disposable, regenerated
data. The keypad glyphs (the "2 ABC" digit-plus-letters marks) are not loaded
from a user-editable store; they are rendered at runtime by
`TelephonyUI.framework` from the system UI font plus the locale strings, then
cached as PNGs. The sysdiagnose confirms the lifecycle: on boot, before first
unlock, `TPFileStorageManager imageWithName:` reads nil, calls
`clearLegacyStorageIfNecessary`, and the versioned cache is wiped and
regenerated fresh. A write that only replaces the cached *output* is therefore
always transient. Making it durable would require changing the generator's
*inputs* (the font, the locale resources, or the render code), all of which
sit on the Signed System Volume — read-only and cryptographically sealed on
iOS 17+/27, with no API to modify and no survival across OS updates. That is
defeating system integrity, not an interface.

Interfaces checked, none of which theme the keypad persistently:

| Interface | Scope | Themes the passcode keypad? |
| --- | --- | --- |
| Public UIKit / SDK | In-app UI | No — the keypad is SpringBoard-private, not exposed |
| MDM / configuration profiles | Passcode *policy* (length, complexity, grace), custom fonts, supervised wallpaper | No payload themes the keypad; installed fonts are not used by it |
| Lock Screen customization (iOS 16+) | Wallpaper, widgets, clock font/color | No — excludes the passcode digit grid |
| Direct cache write (current approach) | Immediately visible | No — regenerated over on boot / read-miss |

The only way to have the theme present after reboot is to re-apply it on each
boot, after the OS has regenerated the default cache and before first unlock.
The data above shows the write itself is not the problem — the theme stays
visible until reboot — what is missing is an automatic re-apply at boot. That
requires resident on-device code (for example a boot-time daemon, or a hook on
`TPFileStorageManager imageWithName:` that returns the custom image), which is
not an Apple-provided interface and is out of reach for the Mac-side AFC tool,
which cannot act during that boot window.

Recommendation: keep positioning the feature as an ephemeral effect (valid
until reboot or cache regeneration), consistent with the findings above. If
the goal is lock-screen customization that persists, the supported surface is
the Lock Screen (wallpaper, widgets, clock), not the passcode keypad. Do not
pursue further cache filename/size/attribute variants for persistence; that
axis has been ruled out.
