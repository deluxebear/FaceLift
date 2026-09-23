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
that replaces the cache has not been identified; do not infer a durable fix
from the current write path. `tools/prepare_exact_passcode_probe.py` prepares
the ten-image comparison payload locally and does not write to a phone.
