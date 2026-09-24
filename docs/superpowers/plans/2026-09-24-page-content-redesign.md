# Page Content Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the content of every FaceLift page and sheet with native macOS controls and layout (grouped Forms, Photos-style card grid, canvas + inspector for theme pages) without changing interactions.

**Architecture:** Page UI lives in `extension ContentView` blocks under `Workspaces/`. Shared styling moves from custom glass helpers in `App/Theme.swift` to system styles plus one small `NoticeBar` view. The two theme pages switch from "controls in detail, preview in inspector" to "phone canvas in detail, `Form` controls in inspector"; `MainWindow` picks detail and inspector content per section. Custom glass helpers are deleted in the last task once nothing uses them.

**Tech Stack:** SwiftUI + AppKit compiled directly with `swiftc` (no Xcode project), deployment target macOS 14, macOS 26 SDK. Python 3 for the localization test and small helper scripts.

**Spec:** `docs/superpowers/specs/2026-09-24-page-content-redesign-design.md`

## Global Constraints

- Deployment target stays `macosx14.0`; any Liquid Glass stays behind `#available(macOS 26.0, *)`.
- Interactions stay the same. Only additions: card context menu (same items as the `⋯` menu) and Export `.passthm` in the toolbar and File menu (⌘E).
- One prominent button per page (toolbar Flash). In-page buttons are `.bordered`/`.borderless`; only an empty-state primary action may use `.borderedProminent`.
- Accent/selection color is `Color.brand` (already applied as root `.tint`). Strokes use `Color(nsColor: .separatorColor)`. No tinted accent fills.
- Warnings: orange icon, `.primary` text.
- Every user-facing string goes through `L()`/`LM()` and exists in both `Resources/en.lproj/Localizable.strings` (value == key) and `Resources/zh-Hans.lproj/Localizable.strings`. zh-Hans terminology: skin = 卡面, flash = 写入, ellipsis = ASCII `...`.
- iPhone mock renderers (`walletPhone`, dialer canvases, `phoneMockupContainer` internals, `KeypadKeySurface`) keep their fixed point sizes and colors.
- No changes to `AppViewModel` logic, device communication or flashing.

## Verification commands (used by every task)

```bash
# Fast Swift typecheck (~3 s). Expected: no output, exit 0.
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
  -target arm64-apple-macosx14.0 -typecheck $(find App Model Workspaces -name '*.swift')

# Localization catalogs cover every L()/LM() key. Expected: "ok".
python3 tests/test_localization.py

# Full app build (both architectures). Expected: ends with "SUCCESS".
./build.sh > /tmp/facelift-build.log 2>&1; tail -3 /tmp/facelift-build.log

# Screenshots of every page (created in Task 1).
tools/capture_pages.sh build/screens/<task> light
tools/capture_pages.sh build/screens/<task> dark
tools/capture_pages.sh build/screens/<task>-min light 900x600
```

Do not run `python3 -m unittest discover` or bare `pytest tests/`: backend tests try to reach a device and hang. They are unaffected by UI work.

There is no SwiftUI test target. Each task's "test" is the typecheck, the localization test, and a screenshot check against the listed expectations. Look at every screenshot you capture (open the PNG) before committing.

## File map (end state)

| File | Change |
|---|---|
| `App/Theme.swift` | Add `NoticeBar`; delete content glass and button helpers (Task 8) |
| `App/MainWindow.swift` | Per-section detail/inspector; grid width constant; `isCanvasTargeted` state; `.exportTheme` |
| `App/MainToolbar.swift` | System prominent style; Creator Export button |
| `App/AppCommands.swift` | File ▸ Export .passthm… (⌘E) |
| `App/WindowState.swift` | `WindowAction.exportTheme` |
| `Model/AppViewModel+Availability.swift` | `canExportCreator` |
| `Workspaces/CardsWorkspace.swift` | New tile, control row, notices, empty state; banner removed |
| `Workspaces/ThemeCanvas.swift` | New: canvas, mockup, dialer canvases |
| `Workspaces/ApplyThemeInspector.swift` | New: Lock Screen inspector, `flashTargetSection` |
| `Workspaces/CreatorInspector.swift` | New: Creator inspector |
| `Workspaces/PasscodeWorkspace.swift` | Only panels and drop/image helpers remain |
| `Workspaces/DeviceWorkspace.swift` | Refined Form |
| `Workspaces/Sheets.swift` | Guide, About, Add Card sheets |
| `tools/capture_pages.sh`, `tools/add_strings.py` | New dev helpers |

## Review Focus

1. **Nested drops on the Creator canvas:** dropping an image on a key in Individual Keys mode must set that key, not the poster (key `onDrop` must win over the canvas `onDrop`). Checked in Task 4 Step 6.
2. **900×600 window with the inspector open:** Creator inspector segmented pickers and button rows must not clip or overflow in zh-Hans at the minimum inspector width (280 pt). Checked in Task 6 Step 6.
3. **Card tile hit areas:** clicking the checkbox must toggle selection only; clicking the artwork must open the image picker only; the context menu must act on the clicked card while a search filter is active. Checked in Task 2 Step 6.
4. **Dark Mode:** placeholder artwork, selection badge, canvas background and `NoticeBar` must stay legible. Checked in every task's dark screenshots.
5. **Keyboard in sheets:** Return in the Add Card `TextEditor` inserts a newline (does not submit while typing); Esc cancels; ⌘E is disabled without configured keys. Checked in Task 8 Step 6 and Task 4 Step 6.

---

### Task 1: Shared foundation — `NoticeBar`, toolbar button style, dev helpers

**Files:**
- Modify: `App/Theme.swift` (append `NoticeBar`)
- Modify: `App/MainToolbar.swift:77,85,94`
- Create: `tools/capture_pages.sh`
- Create: `tools/add_strings.py`

**Interfaces:**
- Produces: `NoticeBar(title: String, message: String? = nil, leading: () -> Leading, trailing: () -> Trailing)` and the `trailing`-less init; `tools/capture_pages.sh OUT_DIR [light|dark] [WxH]`; `python3 tools/add_strings.py '<json {key: zh}>'`.

- [ ] **Step 1: Capture "before" screenshots**

Create `tools/capture_pages.sh`:

```bash
#!/usr/bin/env bash
# Screenshot every FaceLift page (⌘1–⌘4) from build/FaceLift.app.
# Usage: tools/capture_pages.sh OUT_DIR [light|dark] [WIDTHxHEIGHT]
# Needs Accessibility permission for the terminal (System Events keystrokes).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: tools/capture_pages.sh OUT_DIR [light|dark] [WIDTHxHEIGHT]}"
MODE="${2:-light}"
SIZE="${3:-}"
mkdir -p "$OUT"

osascript -e 'tell application "FaceLift" to quit' >/dev/null 2>&1 || true
sleep 1
if [ "$MODE" = dark ]; then STYLE=Dark; else STYLE=Light; fi
open build/FaceLift.app --args -AppleInterfaceStyle "$STYLE"
sleep 3

if [ -n "$SIZE" ]; then
  osascript -e "tell application \"System Events\" to tell process \"FaceLift\" to set size of front window to {${SIZE%x*}, ${SIZE#*x}}"
  sleep 1
fi

HELPER="$(mktemp -t facelift-wid).swift"
cat > "$HELPER" <<'EOF'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
for w in windows where (w["kCGWindowOwnerName"] as? String) == "FaceLift" && (w["kCGWindowLayer"] as? Int) == 0 {
    print(w["kCGWindowNumber"]!); break
}
EOF
WID="$(swift "$HELPER")"
rm -f "$HELPER"

for i in 1 2 3 4; do
  osascript -e 'tell application "FaceLift" to activate' \
            -e "tell application \"System Events\" to keystroke \"$i\" using command down"
  sleep 1.5
  screencapture -o -l"$WID" "$OUT/${MODE}${SIZE:+-$SIZE}-page$i.png"
done
echo "Saved to $OUT"
```

Run:

```bash
chmod +x tools/capture_pages.sh
./build.sh > /tmp/facelift-build.log 2>&1; tail -3 /tmp/facelift-build.log
tools/capture_pages.sh build/screens/before light
tools/capture_pages.sh build/screens/before dark
tools/capture_pages.sh build/screens/before light 900x600
```

Expected: 12 PNGs in `build/screens/before/` (`build/` is git-ignored).

- [ ] **Step 2: Create the string helper**

Create `tools/add_strings.py`:

```python
#!/usr/bin/env python3
"""Append interface strings to both catalogs.

Usage: python3 tools/add_strings.py '{"English key": "中文", ...}'
Keys already present are skipped. English values always equal the key.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def quote(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    entries = json.loads(sys.argv[1])
    for lang in ("en", "zh-Hans"):
        path = ROOT / "Resources" / f"{lang}.lproj" / "Localizable.strings"
        text = path.read_text()
        lines = [
            f'"{quote(key)}" = "{quote(key if lang == "en" else zh)}";'
            for key, zh in entries.items()
            if f'"{quote(key)}" =' not in text
        ]
        if lines:
            path.write_text(text.rstrip("\n") + "\n" + "\n".join(lines) + "\n")
        print(f"{lang}: added {len(lines)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Add `NoticeBar` to `App/Theme.swift`**

Append at the end of the file:

```swift
// MARK: - In-page notice

/// Compact in-page notice (card scanning, hidden selection): control
/// background with a hairline separator border.
struct NoticeBar<Leading: View, Trailing: View>: View {
    let title: String
    var message: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(message == nil ? .callout : .callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

extension NoticeBar where Trailing == EmptyView {
    init(title: String, message: String? = nil, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, message: message, leading: leading, trailing: { EmptyView() })
    }
}
```

- [ ] **Step 4: Toolbar Flash buttons use the system prominent style**

In `App/MainToolbar.swift`, replace each of the three `.faceLiftProminentButton()` lines (Cards, Lock Screen, Creator flash buttons) with:

```swift
            .buttonStyle(.borderedProminent)
```

- [ ] **Step 5: Verify**

Run the typecheck and `python3 tests/test_localization.py`. Expected: no output / `ok`. Build and capture `build/screens/t1` light. Expected: the toolbar Flash button is still a filled accent button (Liquid Glass tinted on macOS 26); nothing else changed.

- [ ] **Step 6: Commit**

```bash
git add App/Theme.swift App/MainToolbar.swift tools/capture_pages.sh tools/add_strings.py
git commit -m "feat(ui): add NoticeBar and page screenshot tooling"
```

---

### Task 2: Cards page

**Files:**
- Modify: `Workspaces/CardsWorkspace.swift` (replace `WalletTileView`, `walletWorkspace`, `walletGridColumns`, `walletPreview` header, `scanningNoticeBanner`, `emptyStateView`)
- Modify: `App/MainWindow.swift` (`threeColumnWorkspaceWidth` in `windowLayout`)
- Modify: both `Localizable.strings`

**Interfaces:**
- Consumes: `NoticeBar` (Task 1).
- Produces: `ContentView.cardCountSummary: String`.

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"%@ cards · %@ selected": "%@ 张卡片 · 已选 %@ 张", "No Cards Yet": "还没有卡片"}'
```

- [ ] **Step 2: Replace `WalletTileView`**

Replace the whole `struct WalletTileView` in `Workspaces/CardsWorkspace.swift` with:

```swift
struct WalletTileView: View {
    @Binding var card: CardItem
    let index: Int
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let onDelete: () -> Void
    let onStoreImage: (URL) -> Void
    @State private var isTargeted = false

    private let artworkShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
            HStack(alignment: .top, spacing: 6) {
                Toggle(isOn: $card.isSelected) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(card.isSelected ? L("Remove from flash") : L("Include in flash"))
                    .accessibilityLabel(Text(L("Card #%@", String(index + 1))))
                    .accessibilityValue(Text(card.isSelected ? L("Selected for flash") : L("Not selected for flash")))
                    .accessibilityHint(Text(card.isSelected ? L("Remove from flash") : L("Include in flash")))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Card #%@", String(index + 1)))
                        .font(.headline)
                    Text(card.customImage == nil ? L("Artwork not set") : L("Artwork ready"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("More"))
            }
            .padding(.horizontal, 3)
        }
        .contextMenu { menuItems }
    }

    private var artwork: some View {
        ZStack {
            if let image = card.customImage {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                artworkPlaceholder
            }
        }
        .aspectRatio(1.59, contentMode: .fit)
        .clipShape(artworkShape)
        .overlay(artworkShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if card.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.brand)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .padding(3) // Room for the selection ring.
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.brand, lineWidth: 3)
                .opacity(card.isSelected || isTargeted ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPickImage)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, NSImage(contentsOf: url) != nil else { return }
                Task { @MainActor in onStoreImage(url) }
            }
            return true
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                Text(L("Add Artwork"))
                    .font(.callout.weight(.medium))
                Text(card.id.prefix(8) + "…" + card.id.suffix(6))
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(L("Change Skin"), action: onPickImage)
        if card.customImage != nil { Button(L("Remove skin"), action: onClearImage) }
        Button(L("Copy full hash")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(card.id, forType: .string)
        }
        Divider()
        Button(L("Remove from list"), role: .destructive, action: onDelete)
    }
}
```

Note: the 0.5 pt separator hairline on the artwork keeps white or black artwork from bleeding into the window background; it is not a tile border.

- [ ] **Step 3: Replace `walletWorkspace` and `walletGridColumns`**

Replace `var walletWorkspace` and `private func walletGridColumns(for:)` with:

```swift
    var walletWorkspace: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(cardCountSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    CardSearchField(
                        text: $cardSearch,
                        placeholder: L("Search cards by hash or number"),
                        focusRequest: window.cardSearchFocusRequest
                    )
                    .frame(minWidth: 150, idealWidth: 240, maxWidth: 280)
                    .accessibilityLabel(Text(L("Search cards by hash or number")))
                    Menu {
                        Button(L("Select All")) { for i in vm.cards.indices { vm.cards[i].isSelected = true } }
                        Button(L("Deselect All")) { for i in vm.cards.indices { vm.cards[i].isSelected = false } }
                        Divider()
                        Button(L("Clear All"), role: .destructive) { vm.clearAllCards() }
                    } label: {
                        Label(L("Selection"), systemImage: "checklist")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(vm.cards.isEmpty)
                }
                if vm.isScanningCards { scanningNoticeBanner }
                if hiddenReadyToFlashCount > 0 {
                    NoticeBar(title: L("Search hides %@ selected card(s) ready to flash. Flashing still includes them.", "\(hiddenReadyToFlashCount)")) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if vm.cards.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        if filteredCardIndices.isEmpty {
                            ContentUnavailableView.search(text: cardSearch)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: walletGridColumns(for: geometry.size.width), spacing: 16) {
                                ForEach(filteredCardIndices, id: \.self) { index in
                                    WalletTileView(
                                        card: $vm.cards[index], index: index,
                                        onPickImage: { openCardImagePicker(for: vm.cards[index].id) },
                                        onClearImage: { vm.clearCardImage(for: vm.cards[index].id) },
                                        onDelete: { vm.deleteCard(id: vm.cards[index].id) },
                                        onStoreImage: { vm.storeSkin(for: vm.cards[index].id, url: $0) }
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
        }
    }

    private func walletGridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(0, width - 40) // Grid's horizontal padding.
        let count = min(3, max(1, Int((availableWidth + 16) / (210 + 16))))
        return Array(repeating: GridItem(.flexible(minimum: 210, maximum: 300), spacing: 16), count: count)
    }

    var cardCountSummary: String {
        L("%@ cards · %@ selected", "\(vm.cards.count)", "\(vm.cards.filter(\.isSelected).count)")
    }
```

This removes the "Make a passcode theme / Open Creator" banner.

- [ ] **Step 4: Update the grid width constant in `App/MainWindow.swift`**

In `windowLayout(width:)` replace:

```swift
        let threeColumnWorkspaceWidth: CGFloat = 3 * 210 + 2 * 13 + 2 * 25
```

with:

```swift
        let threeColumnWorkspaceWidth: CGFloat = 3 * 210 + 2 * 16 + 2 * 20
```

- [ ] **Step 5: Replace preview header, scanning banner and empty state**

In `walletPreview`, delete the first `HStack { Text(L("Live Preview")) … }.padding(.bottom, 13)` block so the `VStack` starts with `walletPhone`.

Replace `var scanningNoticeBanner` and `var emptyStateView` with:

```swift
    var scanningNoticeBanner: some View {
        NoticeBar(
            title: L("Live Scanner Active"),
            message: L("Double-click Side button (Apple Pay), pass Face ID, then tap your card.")
        ) {
            ProgressView().controlSize(.small)
        } trailing: {
            Button(L("Done")) { vm.stopCardScanning() }
                .controlSize(.small)
        }
    }

    var emptyStateView: some View {
        ContentUnavailableView {
            Label(L("No Cards Yet"), systemImage: "creditcard.viewfinder")
        } description: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) { Text("1."); LM("Click **Scan Cards** in the toolbar above.") }
                HStack(alignment: .top, spacing: 6) { Text("2."); LM("On your iPhone, **double-click the Side button** (Apple Pay), authenticate with **Face ID**, and **tap your card**.") }
                HStack(alignment: .top, spacing: 6) { Text("3."); Text(L("Your card will be detected immediately!")) }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 420)
        } actions: {
            Button(L("Start Scanning")) { vm.startCardScanning() }
                .buttonStyle(.borderedProminent)
                .disabled(vm.device?.connected != true)
            Button(L("Add Hashes Manually")) { vm.showAddCardSheet = true }
                .buttonStyle(.bordered)
        }
    }
```

- [ ] **Step 6: Verify**

Typecheck, localization test, build, then capture `build/screens/t2` light, dark and light 900x600. Expected on page 1:
- No tile panel/shadow; artwork with 10 pt corners; selected cards have a brand ring and a white-on-brand check badge.
- Control row shows "5 张卡片 · 已选 5 张" (or English equivalent).
- No "制作专属密码主题" banner; no "实时预览" title in the inspector.
- Dark: placeholder and badge legible.

Manual (Review Focus 3): in the running app, click a checkbox (selection toggles, no file panel), click the artwork (file panel opens; cancel), type `#2`-style search `2`, right-click the visible card ▸ Copy full hash, and confirm the pasteboard holds that card's hash (`pbpaste`). Start scanning with a device if available (notice bar with spinner and Done).

- [ ] **Step 7: Commit**

```bash
git add Workspaces/CardsWorkspace.swift App/MainWindow.swift Resources
git commit -m "feat(ui): restyle cards page as a native thumbnail grid"
```

---

### Task 3: Split `PasscodeWorkspace.swift` (no logic changes)

**Files:**
- Create: `Workspaces/ThemeCanvas.swift`, `Workspaces/ApplyThemeInspector.swift`, `Workspaces/CreatorInspector.swift`
- Modify: `Workspaces/PasscodeWorkspace.swift`

**Interfaces:**
- Produces: the same `ContentView` members as before, now in: `ThemeCanvas.swift` (`applyThemeDialerCanvas`, `scaledPosterDimensions(for:)`, `creatorDialerCanvas`, `creatorButtonView(for:)`, `phoneMockupContainer(content:)`), `ApplyThemeInspector.swift` (`passcodeApplyThemeWorkspaceView`, `applyThemeControlsCard`, `targetSettingsCard`), `CreatorInspector.swift` (`passcodeThemeCreatorWorkspaceView`, `creatorControlsCard`).

- [ ] **Step 1: Split with a line-range script**

The ranges match the file at commit `fe1fab6`; the script asserts anchor lines and stops if the file differs.

```bash
python3 - <<'EOF'
from pathlib import Path
src = Path("Workspaces/PasscodeWorkspace.swift")
lines = src.read_text().split("\n")
def at(n): return lines[n - 1].strip()
anchors = {
    71: "// MARK: - Apply Theme Mode", 208: "}",
    210: "var applyThemeDialerCanvas: some View {", 251: "}",
    253: "// MARK: - Theme Creator Mode", 576: "}",
    578: "func scaledPosterDimensions(for poster: NSImage) -> (width: CGFloat, height: CGFloat) {",
    829: "}", 831: "// MARK: - Passcode Target Configuration Box", 901: "}", 903: "}",
}
for n, text in anchors.items():
    assert at(n) == text, (n, at(n))
header = "import SwiftUI\nimport AppKit\nimport UniformTypeIdentifiers\n\nextension ContentView {\n"
def chunk(*ranges):
    body = []
    for a, b in ranges:
        body += lines[a - 1:b] + [""]
    return header + "\n".join(body).rstrip() + "\n}\n"
Path("Workspaces/ThemeCanvas.swift").write_text(chunk((210, 251), (578, 829)))
Path("Workspaces/ApplyThemeInspector.swift").write_text(chunk((71, 208), (831, 901)))
Path("Workspaces/CreatorInspector.swift").write_text(chunk((253, 576)))
moved = set()
for a, b in [(71, 208), (210, 251), (253, 576), (578, 829), (831, 901)]:
    moved.update(range(a, b + 1))
src.write_text("\n".join(l for i, l in enumerate(lines, 1) if i not in moved))
EOF
```

- [ ] **Step 2: Verify**

Typecheck (expected: no output) and `python3 tests/test_localization.py` (expected: `ok`). Then:

```bash
wc -l Workspaces/PasscodeWorkspace.swift Workspaces/ThemeCanvas.swift Workspaces/ApplyThemeInspector.swift Workspaces/CreatorInspector.swift
git diff --stat
```

Expected: `PasscodeWorkspace.swift` ≈ 190 lines; total lines across the four files ≈ original 1028 + 3×7 header/footer lines. Build and capture `build/screens/t3` light: pages 2 and 3 look identical to `build/screens/before`.

- [ ] **Step 3: Commit**

```bash
git add Workspaces
git commit -m "refactor: split passcode workspace into canvas and inspector files"
```

---

### Task 4: Theme canvas, per-section inspector, Export command

**Files:**
- Modify: `Workspaces/ThemeCanvas.swift` (add `themeCanvas`, `canvasCaption`; scale cap)
- Modify: `Workspaces/PasscodeWorkspace.swift` (delete `passcodePreview`; add `handleThemeDrop(providers:)`)
- Modify: `App/MainWindow.swift` (detail/inspector switch, `isCanvasTargeted`, `perform(.exportTheme)`)
- Modify: `App/WindowState.swift`, `App/MainToolbar.swift`, `App/AppCommands.swift`, `Model/AppViewModel+Availability.swift`
- Modify: both `Localizable.strings`

**Interfaces:**
- Consumes: `phoneMockupContainer`, `applyThemeDialerCanvas`, `creatorDialerCanvas`, `handlePosterDrop(providers:)`, `openSavePasscodeThemePanel()`.
- Produces: `ContentView.themeCanvas`, `ContentView.handleThemeDrop(providers: [NSItemProvider]) -> Bool`, `@State var isCanvasTargeted`, `WindowAction.exportTheme`, `AppViewModel.canExportCreator: Bool`.

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"Previewing at %@ size": "按 %@ 尺寸预览"}'
```

- [ ] **Step 2: Add the canvas**

In `Workspaces/ThemeCanvas.swift`, inside `phoneMockupContainer`, change:

```swift
            let scale = max(0.1, min(1, (proxy.size.width - 12) / baseWidth, (proxy.size.height - 12) / baseHeight))
```

to:

```swift
            let scale = max(0.1, min(1.25, (proxy.size.width - 12) / baseWidth, (proxy.size.height - 12) / baseHeight))
```

Add at the top of the `extension ContentView {` block:

```swift
    /// Lock Screen / Creator detail area: the phone mockup centered on a
    /// canvas that also accepts the page's file drops.
    var themeCanvas: some View {
        let isApply = vm.passcodeTabMode == .applyTheme
        return VStack(spacing: 12) {
            phoneMockupContainer {
                if isApply {
                    applyThemeDialerCanvas
                } else {
                    creatorDialerCanvas
                }
            }
            VStack(spacing: 4) {
                if isApply && vm.loadedPasscodeTheme == nil {
                    Text(L("Drop .passthm file here"))
                        .font(.callout.weight(.medium))
                }
                Text(canvasCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay {
            if isCanvasTargeted {
                Rectangle().strokeBorder(Color.brand, lineWidth: 3)
            }
        }
        .onDrop(
            of: isApply ? [UTType.fileURL, UTType.data] : [UTType.fileURL, UTType.image],
            isTargeted: $isCanvasTargeted
        ) { providers in
            isApply ? handleThemeDrop(providers: providers) : handlePosterDrop(providers: providers)
        }
    }

    var canvasCaption: String {
        vm.device?.connected == true
            ? L("Previewing at %@ size", vm.device?.name ?? "iPhone")
            : L("iPhone Preview")
    }

```

- [ ] **Step 3: Drop helper, remove old preview**

In `Workspaces/PasscodeWorkspace.swift`, delete the whole first `extension ContentView { var passcodePreview … }` block. In the helpers extension, add after `handlePosterDrop(providers:)`:

```swift
    func handleThemeDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url else { return }
            Task { @MainActor in vm.inspectPasscodeTheme(url: url) }
        }
        return true
    }
```

- [ ] **Step 4: Window wiring**

`App/MainWindow.swift`:
- After `@State var isTargetedTheme = false` add `@State var isCanvasTargeted = false`.
- In `detail`, change `case .passcode, .creator: passcodeWorkspace` to `case .passcode, .creator: themeCanvas`.
- In `inspectorContent`, change `case .passcode, .creator: passcodePreview` to `case .passcode, .creator: passcodeWorkspace` (temporary; Tasks 5–6 replace it).
- In `perform(_:)` add before `case .clearTheme:`:

```swift
        case .exportTheme:
            openSavePasscodeThemePanel()
```

`App/WindowState.swift`: add `case exportTheme` after `case clearCreator` in `WindowAction`.

`Model/AppViewModel+Availability.swift`: after `canFlashCreator` add:

```swift
    var canExportCreator: Bool { !effectiveCreatorKeys.isEmpty }
```

`App/MainToolbar.swift`, in `pageActions` `case .creator:`, after the Choose Poster button and before `targetVersionPicker`, add:

```swift
            Button { perform(.exportTheme) } label: {
                Label(L("Export .passthm..."), systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.canExportCreator)
            .help(L("Export .passthm..."))
```

`App/AppCommands.swift`, in `CommandGroup(replacing: .newItem)` after the Choose Poster button, add:

```swift
            Button(L("Export .passthm...")) { window?.send(.exportTheme) }
                .keyboardShortcut("e")
                .disabled(isBlocked || window?.section != .creator || vm?.canExportCreator != true)
```

- [ ] **Step 5: Typecheck and localization**

Expected: no output / `ok`.

- [ ] **Step 6: Verify**

Build, capture `build/screens/t4` light and dark. Expected on pages 2–3: phone centered on a gray canvas with the caption below; old controls now in the inspector (temporary). Manual:
- Lock Screen: drag a `.passthm` onto the canvas → brand ring while dragging, theme loads.
- Creator, Poster Slice: drag an image onto the canvas → poster set; drag on the keypad pans the poster.
- Creator, Individual Keys (Review Focus 1): drop an image onto key 5 → only key 5 changes, the poster does not.
- ⌘E with no keys: menu item disabled; after loading the example poster, ⌘E opens the save panel (cancel it). Toolbar export button follows the same enablement.

- [ ] **Step 7: Commit**

```bash
git add App Model Workspaces Resources
git commit -m "feat(ui): center theme preview on a canvas and add Export command"
```

---

### Task 5: Lock Screen inspector

**Files:**
- Modify: `Workspaces/ApplyThemeInspector.swift` (replace contents)
- Modify: `Workspaces/PasscodeWorkspace.swift` (`passcodeThemeWorkspaceView`)
- Modify: `App/MainWindow.swift` (inspector switch; remove `isTargetedTheme`)
- Modify: both `Localizable.strings`

**Interfaces:**
- Produces: `ContentView.applyThemeInspector`, `ContentView.flashTargetSection` (used by Task 6). `targetSettingsCard` stays until Task 6 because the old Creator view still uses it.

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"No theme selected": "未选择主题", "%@ artwork assets": "%@ 个图片资源", "Keyboard Language": "键盘语言", "Font Weight": "字体粗细", "Flash Target": "写入目标"}'
```

- [ ] **Step 2: Replace `Workspaces/ApplyThemeInspector.swift`**

Delete `// MARK: - Apply Theme Mode`, `var passcodeApplyThemeWorkspaceView` and `var applyThemeControlsCard` (everything above `// MARK: - Passcode Target Configuration Box` inside the extension). Keep `var targetSettingsCard` unchanged: the old Creator view still uses it until Task 6. Insert the following members at the top of the `extension ContentView {` block:

```swift
    var applyThemeInspector: some View {
        Form {
            Section(L("Passcode Theme File")) {
                if let theme = vm.loadedPasscodeTheme {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.square.stack.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(theme.supportedVersions.count > 1
                                 ? L("Supports %@", theme.supportedVersions.joined(separator: ", "))
                                 : theme.detectedVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L("%@ artwork assets", "\(theme.fileCount)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button { vm.editLoadedThemeInCreator() } label: {
                        Label(L("Edit in Creator"), systemImage: "pencil.and.outline")
                    }
                } else {
                    LabeledContent {
                        Button(L("Choose File...")) { openPasscodeThemePicker() }
                    } label: {
                        Text(L("No theme selected"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            flashTargetSection
        }
        .formStyle(.grouped)
    }

    /// Language and weight targets shared by the Lock Screen and Creator inspectors.
    var flashTargetSection: some View {
        let isUniversal = vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both
        return Section {
            Picker(L("Keyboard Language"), selection: $vm.passcodeLanguageTarget) {
                ForEach(PasscodeLanguageTarget.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Picker(L("Font Weight"), selection: $vm.passcodeBoldTarget) {
                ForEach(PasscodeBoldTarget.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
        } header: {
            Text(L("Flash Target"))
        } footer: {
            Text(isUniversal
                 ? L("Universal mode flashes ~600 files for all languages & Bold text. Selecting a specific language (e.g. Ukrainian) speeds up flashing dramatically.")
                 : L("Fast mode selected: only targets %@ with %@.", vm.passcodeLanguageTarget.title, vm.passcodeBoldTarget.title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

```

- [ ] **Step 3: Rewire**

`Workspaces/PasscodeWorkspace.swift`: replace the body of `var passcodeThemeWorkspaceView` with:

```swift
    var passcodeThemeWorkspaceView: some View {
        passcodeThemeCreatorWorkspaceView
    }
```

`App/MainWindow.swift`: delete `@State var isTargetedTheme = false`; in `inspectorContent` replace `case .passcode, .creator: passcodeWorkspace` with:

```swift
        case .passcode: applyThemeInspector
        case .creator: passcodeWorkspace
```

- [ ] **Step 4: Typecheck and localization**

Expected: no output / `ok`. If the typecheck reports `isTargetedTheme` still referenced, you missed deleting `applyThemeControlsCard`.

- [ ] **Step 5: Verify**

Build, capture `build/screens/t5` light, dark and 900x600. Expected page 2 inspector: grouped Form, "密码主题文件" section with "未选择主题" and 选择文件… on one row; "写入目标" section with two label-left pickers and the footer hint; no dashed drop zone; no bottom long button. Manual: ⌘O a theme → the row shows name, versions, asset count and 在制作器中编辑; click it → switches to Creator with the theme loaded.

- [ ] **Step 6: Commit**

```bash
git add App Workspaces Resources
git commit -m "feat(ui): move lock screen theme controls into a grouped inspector"
```

---

### Task 6: Creator inspector

**Files:**
- Modify: `Workspaces/CreatorInspector.swift` (replace contents)
- Modify: `Workspaces/ApplyThemeInspector.swift` (delete `targetSettingsCard`)
- Modify: `Workspaces/PasscodeWorkspace.swift` (delete `passcodeWorkspace`, `passcodeThemeWorkspaceView`)
- Modify: `Workspaces/ThemeCanvas.swift` (context menu uses `resetIndividualKey`)
- Modify: `App/MainWindow.swift` (inspector switch; remove `isTargetedPoster`)
- Modify: both `Localizable.strings`

**Interfaces:**
- Consumes: `flashTargetSection` (Task 5), `openPosterPicker()`, `openIndividualKeyPicker(for:)`.
- Produces: `ContentView.creatorInspector`, `ContentView.resetIndividualKey(_ digit: String)`.

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"Mode": "模式", "No poster selected": "未选择海报", "Framing": "取景", "Drag on the preview to reposition": "在预览上拖动以调整位置", "Configured": "已设置", "%@ of 10": "%@ / 10", "Key %@": "按键 %@"}'
```

- [ ] **Step 2: Replace `Workspaces/CreatorInspector.swift`**

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var creatorInspector: some View {
        Form {
            Section {
                Picker(L("Mode"), selection: $vm.creatorSubMode) {
                    ForEach(CreatorSubMode.allCases) { subMode in
                        Text(subMode.title).tag(subMode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if vm.creatorSubMode == .posterSlice {
                posterSection
                slicingStyleSection
                framingSection
            } else {
                keysSection
                if let digit = vm.selectedKeyDigit,
                   vm.creatorRawIndividualImages[digit] != nil || vm.creatorCustomKeys[digit] != nil {
                    selectedKeySection(digit)
                }
            }
            flashTargetSection
        }
        .formStyle(.grouped)
    }

    private var posterSection: some View {
        Section(L("Poster Artwork")) {
            if let poster = vm.creatorPosterImage {
                HStack(spacing: 10) {
                    Image(nsImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                    Text(L("Artwork Loaded"))
                    Spacer(minLength: 4)
                    Button(L("Change...")) { openPosterPicker() }
                    Menu {
                        Button(L("Use Chinese Numeral Example")) { vm.loadDefaultPoster() }
                        Divider()
                        Button(L("Remove"), role: .destructive) { vm.clearCreator() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("More"))
                }
            } else {
                LabeledContent {
                    Button(L("Choose Image...")) { openPosterPicker() }
                } label: {
                    Text(L("No poster selected"))
                        .foregroundStyle(.secondary)
                }
                Button(L("Use Chinese Numeral Example")) { vm.loadDefaultPoster() }
                    .buttonStyle(.link)
            }
        }
    }

    private var slicingStyleSection: some View {
        Section {
            Picker(L("Slicing Style"), selection: $vm.creatorMaskToCircles) {
                Text(L("Seamless Poster")).tag(false)
                Text(L("Circle Buttons")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: vm.creatorMaskToCircles) { _, _ in
                vm.updatePosterSlicing()
            }
        } header: {
            Text(L("Slicing Style"))
        } footer: {
            Text(vm.creatorMaskToCircles
                 ? L("Artwork is clipped into individual circular button icons.")
                 : L("Seamless artwork spans across dialer keys without circular cuts (Adobe Dog style)."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var framingSection: some View {
        Section {
            LabeledContent(L("Zoom")) {
                zoomSlider($vm.creatorPosterZoom)
            }
            .disabled(vm.creatorPosterImage == nil)
            .onChange(of: vm.creatorPosterZoom) { _, _ in
                vm.updatePosterSlicing()
            }
        } header: {
            HStack {
                Text(L("Framing"))
                Spacer()
                Button(L("Reset")) {
                    withAnimation(.spring()) {
                        vm.creatorPosterZoom = 1.0
                        vm.creatorPosterOffset = .zero
                        dragOffsetStart = .zero
                        vm.updatePosterSlicing()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(vm.creatorPosterImage == nil)
            }
        } footer: {
            Text(L("Drag on the preview to reposition"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var keysSection: some View {
        Section {
            LabeledContent(L("Configured"), value: L("%@ of 10", "\(vm.creatorCustomKeys.count)"))
            HStack {
                if !vm.creatorSlicedKeys.isEmpty {
                    Button(L("Fill from Poster")) { vm.adoptPosterSlicesToIndividualKeys() }
                }
                Button(L("Clear All Keys")) { vm.clearAllIndividualKeys() }
                    .disabled(vm.creatorCustomKeys.isEmpty)
            }
        } header: {
            Text(L("Individual Keys"))
        } footer: {
            Text(L("Click any key on the dialer to select it, pan the image, adjust zoom, or drop files."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedKeySection(_ digit: String) -> some View {
        Section {
            LabeledContent(L("Zoom")) {
                zoomSlider(Binding(
                    get: { vm.creatorIndividualZooms[digit] ?? 1.0 },
                    set: { newValue in
                        vm.creatorIndividualZooms[digit] = newValue
                        vm.updateIndividualKey(digit: digit)
                    }
                ))
            }
            HStack {
                Button(L("Change Image...")) { openIndividualKeyPicker(for: digit) }
                Button(L("Reset")) { withAnimation(.spring()) { resetIndividualKey(digit) } }
                Button(L("Remove")) { vm.clearIndividualKey(digit: digit) }
            }
            .controlSize(.small)
        } header: {
            HStack {
                Text(L("Key %@", digit))
                Spacer()
                Button(L("Done")) { vm.selectedKeyDigit = nil }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        } footer: {
            Text(L("Drag Key %@ on dialer preview to reposition", digit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func zoomSlider(_ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: 0.5...3.0, step: 0.05) {
                Text(L("Zoom"))
            } minimumValueLabel: {
                Image(systemName: "minus.magnifyingglass")
            } maximumValueLabel: {
                Image(systemName: "plus.magnifyingglass")
            }
            .labelsHidden()
            Text(String(format: "%.1fx", value.wrappedValue))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    func resetIndividualKey(_ digit: String) {
        vm.creatorIndividualOffsets[digit] = .zero
        vm.creatorIndividualZooms[digit] = 1.0
        dragKeyStartOffsets[digit] = .zero
        vm.updateIndividualKey(digit: digit)
    }
}
```

- [ ] **Step 3: Reuse `resetIndividualKey` in the key context menu**

In `Workspaces/ThemeCanvas.swift`, `creatorButtonView(for:)` `.contextMenu`, replace the "Reset Position & Zoom" button body:

```swift
                    Button(L("Reset Position & Zoom")) {
                        resetIndividualKey(btn.digit)
                    }
```

- [ ] **Step 4: Remove the old Creator/target views and state**

- `Workspaces/ApplyThemeInspector.swift`: delete the `// MARK: - Passcode Target Configuration Box` comment and `var targetSettingsCard`.
- `Workspaces/PasscodeWorkspace.swift`: delete the extension containing `var passcodeWorkspace` and the one containing `var passcodeThemeWorkspaceView`.
- `App/MainWindow.swift`: delete `@State var isTargetedPoster = false`; replace `case .creator: passcodeWorkspace` in `inspectorContent` with `case .creator: creatorInspector`.

Then confirm nothing references removed members:

```bash
grep -rn "passcodeWorkspace\|passcodeThemeWorkspaceView\|passcodeThemeCreatorWorkspaceView\|creatorControlsCard\|targetSettingsCard\|isTargetedPoster\|isTargetedTheme" App Workspaces
```

Expected: no output.

- [ ] **Step 5: Typecheck and localization**

Expected: no output / `ok`.

- [ ] **Step 6: Verify**

Build, capture `build/screens/t6` light, dark, and light 900x600 with zh-Hans (Review Focus 2). Expected page 3 inspector: mode segmented control; 海报图片 row with thumbnail, 更换... and `⋯`; 切片样式 segmented + footer; 取景 with 重置 in the header and a zoom row reading "1.0x"; 写入目标 section. At 900×600 nothing is clipped or overflows horizontally. Manual:
- Zoom slider moves the canvas poster; 重置 restores it.
- Switch to 单独按键: 已设置 "N / 10", 从海报填充, 清除全部按键; click a key with an image → "按键 5" section appears; 完成 hides it; slider zooms that key; right-click a key ▸ Reset Position & Zoom works.

- [ ] **Step 7: Commit**

```bash
git add App Workspaces Resources
git commit -m "feat(ui): move theme creator controls into a grouped inspector"
```

---

### Task 7: Device page

**Files:**
- Modify: `Workspaces/DeviceWorkspace.swift` (replace contents)
- Modify: `Workspaces/Sheets.swift` (`instructionRow`)
- Modify: both `Localizable.strings`

**Interfaces:**
- Produces: restyled `instructionRow(_:_:)` (same signature; also used by the Guide sheet).

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"Connection": "连接方式"}'
```

- [ ] **Step 2: Replace `Workspaces/DeviceWorkspace.swift`**

```swift
import SwiftUI

extension ContentView {
    var deviceWorkspace: some View {
        let device = vm.device
        let connected = device?.connected == true
        return Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(deviceStatusColor(device))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                                .offset(x: 4, y: 2)
                        }
                        .frame(width: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.title3.weight(.semibold))
                        Text(deviceSubtitle(device))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if connected {
                    LabeledContent(L("Model"), value: device?.product ?? "iPhone")
                    LabeledContent(L("iOS Version"), value: device?.version ?? "—")
                    LabeledContent(L("Connection"), value: device?.isWiFi == true ? L("Wi-Fi") : L("USB"))
                }
            }
            if connected && device?.isWiFi == true {
                Section {
                    Label {
                        Text(L("Reading card artwork requires USB. Reconnect with a cable."))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section(L("How to connect")) {
                instructionRow("1", L("Connect iPhone to your Mac with USB."))
                instructionRow("2", L("Unlock iPhone and tap Trust This Computer."))
                instructionRow("3", L("For card scanning, open Apple Pay and tap each card."))
            }
        }
        .formStyle(.grouped)
    }

    private func deviceSubtitle(_ device: DeviceInfo?) -> String {
        guard device?.connected == true else { return L("Waiting for device") }
        let via = device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")
        return "iOS \(device?.version ?? "—") · \(via)"
    }
}
```

- [ ] **Step 3: Restyle `instructionRow` in `Workspaces/Sheets.swift`**

```swift
    func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            Text(text)
        }
    }
```

- [ ] **Step 4: Verify**

Typecheck and localization (`ok`). Build, capture `build/screens/t7` light and dark. Expected page 4: header with gray iPhone symbol and colored status dot, name, "iOS 27.0 · 已通过 Wi-Fi 连接" in secondary; 型号 / iOS 版本 / 连接方式 rows; Wi-Fi warning with orange icon and normal-color text; step numbers on gray circles.

- [ ] **Step 5: Commit**

```bash
git add Workspaces Resources
git commit -m "feat(ui): refine device page form"
```

---

### Task 8: Sheets and removal of content glass helpers

**Files:**
- Modify: `Workspaces/Sheets.swift` (`guideSheet`, `creditsSheet`, `addCardSheet`)
- Modify: `App/Theme.swift` (delete helpers)
- Modify: both `Localizable.strings`

**Interfaces:**
- Consumes: `instructionRow` (Task 7).

- [ ] **Step 1: Add strings**

```bash
python3 tools/add_strings.py '{"Version %@": "版本 %@"}'
```

- [ ] **Step 2: Replace `guideSheet`**

```swift
    var guideSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("FaceLift Guide"))
                .font(.headline)
            guideGroup(L("Cards"), steps: [
                L("Connect iPhone to your Mac with USB."),
                L("Scan Wallet cards, or add a card hash manually."),
                L("Choose artwork, select cards, then write the skins."),
            ])
            guideGroup(L("Lock Screen Themes"), steps: [
                L("Import a passcode theme or create one from images."),
                L("Review the preview and write the theme to iPhone."),
            ])
            HStack {
                Spacer()
                Button(L("Done")) { showGuide = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func guideGroup(_ title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                instructionRow("\(offset + 1)", step)
            }
        }
    }
```

- [ ] **Step 3: Replace `creditsSheet`**

```swift
    var creditsSheet: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("FaceLift")
                    .font(.title3.weight(.semibold))
                Text(L("Version %@", appVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(L("Apple Wallet Skins & Passcode Themes for iOS 18+"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                creditRow(L("Developer & Maintainer:")) {
                    Link("@jetems", destination: URL(string: "https://github.com/jetems")!)
                }
                creditRow(L("AirCard Author:")) {
                    HStack(spacing: 4) {
                        Link("@mak5er", destination: URL(string: "https://github.com/mak5er")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Twitter / X", destination: URL(string: "https://x.com/mak5er")!)
                    }
                }
                creditRow(L("AirCard Contributor:")) {
                    HStack(spacing: 4) {
                        Link("@Lumid-Off", destination: URL(string: "https://github.com/Lumid-Off")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Twitter / X", destination: URL(string: "https://x.com/LumidOff")!)
                    }
                }
                creditRow(L("Based on:")) {
                    HStack(spacing: 4) {
                        Link("AirCard v1.2.3", destination: URL(string: "https://github.com/mak5er/AirCard")!)
                        Text(L("(MIT License)")).foregroundStyle(.secondary)
                    }
                }
                creditRow(L("Core Exploit:")) {
                    Text(L("airlift (AirTraffic sync escape)"))
                }
                creditRow(L("Passcode Themes:")) {
                    Text(L(".passthm standard (Cowabunga / Nugget)"))
                }
            }
            .font(.callout)
            HStack {
                Spacer()
                Button(L("Done")) { showCredits = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func creditRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .gridColumnAlignment(.leading)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
```

- [ ] **Step 4: Replace `addCardSheet`**

```swift
    var addCardSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Add Card Hashes Manually"))
                .font(.headline)
            Text(L("Paste one or more card hashes (separated by spaces, commas, or newlines):"))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $vm.manualHashInput)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            Text(L("Use a hash previously scanned by FaceLift or saved in a card backup. Adding a hash only saves it to this list; it does not create or verify a card on your iPhone."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !manualHashFeedback.isEmpty {
                Text(manualHashFeedback)
                    .font(.caption)
                    .foregroundStyle(Color.brand)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) {
                    vm.showAddCardSheet = false
                    vm.manualHashInput = ""
                    manualHashFeedback = ""
                }
                .keyboardShortcut(.cancelAction)
                Button(L("Add to List")) {
                    let result = vm.addCardHash(vm.manualHashInput)
                    if result.rejected.isEmpty {
                        vm.showAddCardSheet = false
                        vm.manualHashInput = ""
                        manualHashFeedback = ""
                    } else {
                        vm.manualHashInput = result.rejected.joined(separator: "\n")
                        manualHashFeedback = result.added > 0
                            ? L("Added %@ card hash(es). Invalid or duplicate entries remain below.", "\(result.added)")
                            : L("No card hashes were added. Check the format or remove duplicates.")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.manualHashInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
```

- [ ] **Step 5: Delete unused helpers from `App/Theme.swift`**

```bash
grep -rn "faceLiftPanel\|faceLiftCapsule\|faceLiftTintedCapsule\|faceLiftProminentButton\|faceLiftSecondaryButton\|faceLiftBannerSurface\|faceLiftDropZoneFill\|faceLiftWorkspacePanel" App Model Workspaces | grep -v "func faceLift"
```

Expected: no output. Then delete those eight `func` definitions from the `extension View` in `App/Theme.swift`, and delete `func faceLiftGlass(_:_:)` if `grep -rn "faceLiftGlass(" App Workspaces` shows no remaining caller. Keep `GlassDesign`, `faceLiftGlassGroup`, `KeypadKeySurface`, `Color.brand`, `deviceStatusColor`, `NoticeBar`.

- [ ] **Step 6: Verify**

Typecheck, localization (`ok`), full build (`SUCCESS`, no new warnings: `grep -i warning /tmp/facelift-build.log` shows nothing new vs. the Task 1 log). Manual (Review Focus 5):
- Help ▸ FaceLift Guide: two groups, Return closes.
- FaceLift ▸ About: app icon, version, aligned credits, links open; Return closes.
- Add Manually: type in the editor and press Return → newline inserted; Esc cancels; clicking Add to List submits; with focus outside the editor, Return submits.

Capture final screenshots `build/screens/after` light, dark and light 900x600 and compare each page to `build/screens/before`.

- [ ] **Step 7: Commit**

```bash
git add App Workspaces Resources
git commit -m "feat(ui): restyle sheets and drop content glass helpers"
```
