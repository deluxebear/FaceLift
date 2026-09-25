# FaceLift 🎴

> **Apple Wallet Card Skinner & Lockscreen Passcode Themer for iOS 18+ (No Jailbreak Required)**  
> **v1.1.0** — Powered by the `airlift` AirTraffic sync exploit.

**Language:** English | [简体中文](README.zh-CN.md)

> [!IMPORTANT]
> **Tested configuration:** So far v1.1.0 has only had real-device testing on **macOS 27** (host) driving an **iPhone 16 Pro on iOS 27.0**. Other macOS or iOS versions should work but are not yet verified — feedback welcome.

---

## Screenshots

| Wallet Cards | Passcode Themes | Theme Creator |
| :---: | :---: | :---: |
| ![Wallet Cards](docs/screenshots/cards.png) | ![Passcode Themes](docs/screenshots/passcode-theme.png) | ![Theme Creator](docs/screenshots/theme-creator.png) |

---

## What's New in v1.1.0
- 📱 **Per-iPhone Card Lists:** Every iPhone now keeps its own cards, skins and history under `~/Library/Application Support/FaceLift/Devices/<udid>/`. FaceLift refuses to write a card to an iPhone whose list does not include it.
- 🛟 **Original Artwork Backup & Restore:** Before the first flash, FaceLift saves each card's untouched artwork byte for byte, and can write it back at any time.
- 🕘 **Artwork History:** Every flash is recorded per card; the artwork currently on the iPhone is marked, and flashed cards are deselected automatically.
- 🔄 **Stale Card Art Fixed on iOS 27:** Wallet's rendered card faces are now truly removed after a flash, so the new artwork shows up instead of the old one.
- 🔍 **More Reliable Card Scanning:** The scanner reads the iPhone's unified log, including Info/Debug events, fixing scans that found no cards on iOS 18.6.2, and reports scanner status in the log.
- ⚡ **Passcode Target Auto-Detect:** The iPhone's keyboard language and Bold Text setting are detected on connect, so passcode themes flash only the files that device needs.

## What's New in v1.0.1
- 🗂️ **Single Card Store:** Your card list now lives only in `~/Library/Application Support/FaceLift/cards.json`. Lists saved by older versions are migrated automatically on first launch, and the old copies are retired so they no longer come back.

## What's New in v1.0.0
- 🎨 **Completely Rebuilt UI:** FaceLift now ships as a native, three-column macOS app — a source-list sidebar (Wallet Cards · Passcode Themes · Theme Creator, with your connected device below), a live iPhone preview in the center, and a contextual inspector on the right. Every surface uses clean, opaque materials for a calm, high-contrast look that stays legible in Light and Dark mode.
- 🖼️ **Read Card Artwork Back from iPhone:** Each card's stored face is pulled into the Mac preview and kept across launches — no more re-assigning skins you already flashed.
- 🎯 **Selective Artwork Reading:** "Read Selected from iPhone" pulls only the checked cards, so large collections stay fast.
- 🔌 **USB vs Wi-Fi Awareness:** The status capsule shows whether your iPhone is connected over USB (green) or a Wi-Fi tunnel (orange), backed by usbmuxd's authoritative transport info. Operations that need USB (like reading artwork) warn you when you're on Wi-Fi.
- 🌏 **Simplified Chinese Interface:** Full zh-Hans localization with a language menu (Follow System / English / 简体中文), including Dutch keypad targets.
- 🖱️ **Drag & Drop Everywhere:** Drop a `.passthm` onto the keypad preview, or an image onto a card or an individual key.

## Features
- 🎨 **Custom Card Skins:** Assign custom artwork, textures, or bank logos to Apple Pay and Wallet cards.
- 🖥️ **Native macOS Interface:** A rebuilt sidebar + preview + inspector layout with opaque, high-contrast surfaces and full Light/Dark mode support.
- 🔢 **Lock Screen Passcode Themes (.passthm):** Apply custom keypad button artwork from popular `.passthm` themes directly to iOS 18+ lockscreen.
- 🧩 **Passcode Theme Creator:** Create custom themes from a single wallpaper (Seamless Poster Slicing) or build key-by-key (Individual Keys).
- 🔍 **Interactive Photo Framing:** Pan and zoom artwork directly inside keypad buttons with real-time iPhone preview.
- ✏️ **Edit Existing .passthm Themes:** Open any Cowabunga or Nugget theme package directly in the creator, tweak button artwork, reposition photos, and re-export or flash.
- ⚡ **Per-Card & Bulk Customization:** Set unique artwork for each card or apply one design across all cards with a single click.
- 📱 **Zero-Hassle Card Detection:** Tap any card in your iPhone's Wallet app to detect its hash in real-time.
- 🚀 **100% Standalone (Universal):** Native support for both **Apple Silicon** and **Intel (x86)** Macs. All required device-communication utilities and image engines are pre-bundled inside the app.
- 📦 **Zero Prerequisites:** No Homebrew, Python packages, or terminal setup required for macOS users.

---

## Installation

### macOS (Universal DMG)
1. Download **`FaceLift.dmg`** from [Releases](https://github.com/deluxebear/FaceLift/releases).
2. Open `FaceLift.dmg` and drag **`FaceLift.app`** into your **Applications** folder.
3. Fully compatible with both **Apple Silicon** and **Intel (x86)** Macs.

> [!NOTE]
> **First Launch on macOS (Gatekeeper):**
> If macOS displays an unidentified developer prompt on first launch:
> - **Method 1 (UI):** Right-click (or Control-click) `FaceLift.app` in Applications ➔ click **Open** ➔ click **Open**.
> - **Method 2 (Terminal):**
>   ```sh
>   sudo xattr -cr /Applications/FaceLift.app
>   ```

---

## How to Customize Apple Wallet Cards
1. Connect your iPhone to your Mac via USB cable and ensure it is unlocked and trusted.
2. In FaceLift, select **Wallet Cards** in the sidebar and click **Scan Cards**.
3. On your iPhone:
   - **Double-click the Side (Power) button** to open Apple Pay.
   - Authenticate with **Face ID**.
   - **Tap your card** (or tap it once more) to trigger instant detection!
4. Click on any card mockup or drag & drop an image directly onto the card.
5. Click **Flash Skins**.
6. Force-close the **Wallet** app on your iPhone from the App Switcher (or reboot) to see your new custom card design!

### If scanning finds no cards

The scanner uses the iPhone's unified log service, including Info/Debug events.
On iOS 18.6.2, the legacy log service can show Wallet activity while omitting the
resource lookup messages that contain card identifiers.

Open **Log** and check for `Connected to the unified device log stream`, then
double-click the side button, authenticate, and tap or switch cards. If the log
reader stops, reconnect and unlock the iPhone, then start another scan. Values
that iOS replaces with `<private>` cannot be recovered by the scanner.

If your device previously connected but scanning found zero cards, please try
this build and report whether it helps. Include your iPhone model, iOS version,
macOS version, and the FaceLift version or commit tested. Avoid posting full
device logs or card identifiers. See [scanner validation](docs/wallet-card-detection.md)
for the verified environment and remaining coverage.

---

## How to Apply Lockscreen Passcode Themes (.passthm)
1. Select **Passcode Themes** in the FaceLift sidebar.
2. Drag & drop any `.passthm` file onto the keypad preview (or click **Choose File...** in the inspector).
3. FaceLift will inspect the theme and display an interactive preview on the numeric keypad (0–9, *, #).
4. Click **Apply Passcode Theme**.
  5. Lock your iPhone to see the custom passcode buttons. On a tested iPhone 16 Pro running iOS 27.0, a reboot regenerated the default keypad even after the theme was applied successfully. Reapply the theme after reboot if needed; persistence across reboot is not currently verified.

> [!TIP]
> **Universal Language & Bold Text Support:**  
> FaceLift automatically expands and flashes custom keypad assets for all system locales (English, Ukrainian, Russian, Spanish, German, French, etc.) and generates both standard and **Bold Text** cache bitmaps (`--white` and `--white-bold`), ensuring your theme works regardless of your iOS language or accessibility display settings!

---

## Building from Source

```sh
git clone https://github.com/deluxebear/FaceLift.git
cd FaceLift
chmod +x build.sh
./build.sh
```
This builds universal binaries (`arm64` + `x86_64`), bundles dependencies into `build/FaceLift.app`, and outputs `build/FaceLift.dmg`.

---

## Contributors
- **[@deluxebear](https://github.com/deluxebear)** (Developer & Maintainer of FaceLift)

FaceLift is forked from **AirCard v1.2.3**, created by:
- **[@mak5er](https://github.com/mak5er)** (Author of AirCard) — [GitHub](https://github.com/mak5er) · [Twitter / X](https://x.com/mak5er)
- **[@Lumid-Off](https://github.com/Lumid-Off)** (AirCard Contributor & Developer) — [GitHub](https://github.com/Lumid-Off) · [Twitter / X](https://x.com/LumidOff)

- **[AirLift](https://github.com/0xjohnnydev/airlift)** by **[0xjohnny (@0xjohnnydev)](https://github.com/0xjohnnydev)**: Original AirTraffic/ATAirlock sandbox escape and proof of concept underlying `AirliftFFI`.

## Credits
- FaceLift is based on **[AirCard v1.2.3](https://github.com/mak5er/AirCard)** by **Johnny Franks (@Mak5er)**, licensed under the MIT License.
- Core exploit based on `airlift` (AirTraffic sync escape).
