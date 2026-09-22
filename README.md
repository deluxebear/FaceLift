# FaceLift 🎴

> **Apple Wallet Card Skinner & Lockscreen Passcode Themer for iOS 18+ (No Jailbreak Required)**  
> **Tested on iOS 27 release.**
> Powered by the `airlift` AirTraffic sync exploit.

**Language:** English | [简体中文](README.zh-CN.md)

---

## What's New in FaceLift
FaceLift continues development from AirCard v1.2.3 with these additions:
- 🖼️ **Read Card Artwork Back from iPhone:** Each card's stored face is pulled into the Mac preview and kept across launches — no more re-assigning skins you already flashed.
- 🎯 **Selective Artwork Reading:** "Read Selected from iPhone" pulls only the checked cards, so large collections stay fast.
- 🔌 **USB vs Wi-Fi Awareness:** The status capsule shows whether your iPhone is connected over USB (green) or a Wi-Fi tunnel (orange), backed by usbmuxd's authoritative transport info. Operations that need USB (like reading artwork) warn you when you're on Wi-Fi.
- 🌏 **Simplified Chinese Interface:** Full zh-Hans localization with a language menu (Follow System / English / 简体中文).
- 🛠️ **Stability Fixes:** Resolved stderr pipe deadlocks, added batch flash with per-file fallback, and fixed drag-and-drop handling.

## Features
- 🎨 **Custom Card Skins:** Assign custom artwork, textures, or bank logos to Apple Pay and Wallet cards.
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
1. Download **`FaceLift.dmg`** from [Releases](https://github.com/jetems/FaceLift/releases).
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
2. In FaceLift, stay on the **Wallet Cards** tab and click **Scan Cards**.
3. On your iPhone:
   - **Double-click the Side (Power) button** to open Apple Pay.
   - Authenticate with **Face ID**.
   - **Tap your card** (or tap it once more) to trigger instant detection!
4. Click on any card mockup or drag & drop an image directly onto the card.
5. Click **Flash Skins**.
6. Force-close the **Wallet** app on your iPhone from the App Switcher (or reboot) to see your new custom card design!

---

## How to Apply Lockscreen Passcode Themes (.passthm)
1. Switch to the **Passcode Themes** tab at the top of FaceLift.
2. Drag & drop any `.passthm` file into the app (or click **Choose .passthm File**).
3. FaceLift will inspect the theme and display an interactive preview on the numeric keypad (0–9, *, #).
4. Click **Apply Passcode Theme**.
5. Restart your iPhone to reload the lock screen cache and see your custom passcode buttons!

> [!TIP]
> **Universal Language & Bold Text Support:**  
> FaceLift automatically expands and flashes custom keypad assets for all system locales (English, Ukrainian, Russian, Spanish, German, French, etc.) and generates both standard and **Bold Text** cache bitmaps (`--white` and `--white-bold`), ensuring your theme works regardless of your iOS language or accessibility display settings!

---

## Building from Source

```sh
git clone https://github.com/jetems/FaceLift.git
cd FaceLift
chmod +x build.sh
./build.sh
```
This builds universal binaries (`arm64` + `x86_64`), bundles dependencies into `build/FaceLift.app`, and outputs `build/FaceLift.dmg`.

---

## Contributors
- **[@jetems](https://github.com/jetems)** (Developer & Maintainer of FaceLift)

FaceLift is forked from **AirCard v1.2.3**, created by:
- **[@mak5er](https://github.com/mak5er)** (Author of AirCard) — [GitHub](https://github.com/mak5er) · [Twitter / X](https://x.com/mak5er)
- **[@Lumid-Off](https://github.com/Lumid-Off)** (AirCard Contributor & Developer) — [GitHub](https://github.com/Lumid-Off) · [Twitter / X](https://x.com/LumidOff)

- **[AirLift](https://github.com/0xjohnnydev/airlift)** by **[0xjohnny (@0xjohnnydev)](https://github.com/0xjohnnydev)**: Original AirTraffic/ATAirlock sandbox escape and proof of concept underlying `AirliftFFI`.

## Credits
- FaceLift is based on **[AirCard v1.2.3](https://github.com/mak5er/AirCard)** by **Johnny Franks (@Mak5er)**, licensed under the MIT License.
- Core exploit based on `airlift` (AirTraffic sync escape).
