# Native macOS Window Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FaceLift's hand-built window chrome with native macOS structure (NavigationSplitView, window toolbar, inspector, Settings scene, menu commands, semantic colors, text styles, Dark Mode) without changing page interactions.

**Architecture:** First split the 5,000-line `FaceLiftApp.swift` mechanically into `App/`, `Model/`, `Workspaces/` (ContentView members become `extension ContentView` blocks). Then replace the skeleton: a `WindowState` object holds window-level UI state and is shared with menu commands via `focusedSceneObject`; `AppViewModel` gains `can…` properties that are the single source of truth for toolbar and menu enablement. Finally a codemod moves page UI to semantic colors and text styles.

**Tech Stack:** SwiftUI + AppKit, compiled directly with `swiftc` (no Xcode project), deployment target macOS 14, macOS 26+ SDK for Liquid Glass. Python 3 for one-off codemods and the localization test.

**Spec:** `docs/superpowers/specs/2026-09-23-native-window-shell-design.md`

## Global Constraints

- Deployment target stays `macosx14.0`; Liquid Glass stays behind `#available(macOS 26.0, *)`.
- Minimum window 900×600; sidebar column 180–260 (ideal 210); inspector column 280–400 (ideal 320).
- Brand accent: light `#1466F2`, dark `#4D8DFF`.
- Every user-facing string goes through `L()`/`LM()` and exists in both `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`. zh-Hans terminology: skin = 卡面, flash = 写入, ellipsis = ASCII `...`.
- Page interactions do not change (that is sub-projects 2–4). Only chrome moves and colors/fonts change.
- iPhone/keypad/card mock renderers (`walletPhone`, `applyThemeDialerCanvas`, `creatorButtonView`, `phoneMockupContainer`, `WalletTileView` card art gradient) keep fixed point sizes and colors: they imitate on-device pixels.
- No backend or device-communication changes.

## Verification commands (used by every task)

```bash
# Fast Swift typecheck (~3 s). Expected: no output, exit 0.
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
  -target arm64-apple-macosx14.0 -typecheck $(find App Model Workspaces -name '*.swift')

# Localization catalogs cover every L()/LM() key. Expected: "ok".
python3 tests/test_localization.py
```

Do not run `python3 -m unittest discover`: the backend tests try to reach a device and hang. They are unaffected by this UI work.

## File map (end state)

| File | Responsibility |
|---|---|
| `App/FaceLiftApp.swift` | `@main`, WindowGroup, Settings scene, commands wiring |
| `App/MainWindow.swift` | `ContentView`: split view, inspector, alerts/sheets, `perform(_:)` |
| `App/MainToolbar.swift` | Per-page window toolbar |
| `App/Sidebar.swift` | Two-group sidebar + device row |
| `App/ActivityStatus.swift` | Toolbar-center status/progress + log popover |
| `App/WindowState.swift` | `WindowState`, `WindowAction` |
| `App/AppCommands.swift` | Menu bar commands |
| `App/SettingsView.swift` | ⌘, Settings window |
| `App/Theme.swift` | Glass helpers, `Color.brand`, `deviceStatusColor` |
| `Model/Models.swift` | DeviceInfo, CardItem, enums, `WorkspaceSection` |
| `Model/AppViewModel.swift` | Existing view model (unchanged) |
| `Model/AppViewModel+Availability.swift` | `can…` enablement checks |
| `Model/Localization.swift` | AppLanguage, `L()`, BackendLocalizer |
| `Model/Keypad.swift` | Keypad layout, slicer, exporter |
| `Workspaces/CardsWorkspace.swift` | Cards page, tile, wallet preview, pickers |
| `Workspaces/PasscodeWorkspace.swift` | Lock Screen + Creator pages, keypad preview, pickers |
| `Workspaces/DeviceWorkspace.swift` | Device page (Form) |
| `Workspaces/PhoneMockup.swift` | Phone preview profile/frame |
| `Workspaces/Sheets.swift` | Guide, Credits, Add Card sheets |

---

### Task 1: Split `FaceLiftApp.swift` into App/Model/Workspaces

Pure move. No behavior change. This commit is the bisection baseline.

**Files:**
- Delete: `FaceLiftApp.swift`
- Create: everything under `App/`, `Model/`, `Workspaces/` listed by the script output
- Modify: `build.sh:119-120`
- Modify: `tests/test_localization.py`
- Temporary (not committed): `build/split_ui.py` (`build/` is git-ignored)

**Interfaces:**
- Produces: `struct ContentView` in `App/MainWindow.swift` with all former `private` members now internal; `extension ContentView` blocks in `Workspaces/*.swift` and `App/ActivityStatus.swift`. Top-level `private` types (`WorkspaceSection`, `FaceLiftPalette`, `WalletTileView`, `PhoneFrontStyle`, `PhonePreviewProfile`, `PhoneFrameChrome`, `faceLiftGlass`) become internal.
- Dead code deleted by the split: `topChrome`, `bottomChrome`, `headerView`, `toolbarView`, `bottomBarView`.

- [ ] **Step 1: Make the localization test read the new directories (it will fail first)**

In `tests/test_localization.py`, replace line 9:

```python
SWIFT = ROOT / "FaceLiftApp.swift"
```

with:

```python
SWIFT_DIRS = [ROOT / "App", ROOT / "Model", ROOT / "Workspaces"]
```

Add this function directly above `def load_catalog(`:

```python
def swift_source() -> str:
    files = sorted(path for directory in SWIFT_DIRS for path in directory.rglob("*.swift"))
    assert files, "no Swift sources found"
    return "\n".join(path.read_text() for path in files)
```

And in `test_catalogs_match_and_cover_the_interface`, replace `lookup_keys(SWIFT.read_text())` with `lookup_keys(swift_source())`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `python3 tests/test_localization.py`
Expected: `AssertionError: no Swift sources found`

- [ ] **Step 3: Write the split script to `build/split_ui.py`**

```python
#!/usr/bin/env python3
"""One-off: split FaceLiftApp.swift into App/, Model/, Workspaces/.

Chunks are located by unique start markers, so the script fails loudly if the
source drifts. ContentView members are moved into `extension ContentView`
blocks; `private` is dropped where a declaration now crosses files.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SRC = ROOT / "FaceLiftApp.swift"
lines = SRC.read_text().split("\n")
HEADER = "import SwiftUI\nimport AppKit\nimport UniformTypeIdentifiers\n"

# (marker, destination, kind) — kind "top" = top-level code,
# "cv" = ContentView member, "drop" = dead code, "cvhead" = ContentView struct head.
TOP = [
    ("// MARK: - Liquid Glass Design System", "App/Theme.swift", "top"),
    ("// MARK: - Interface language", "Model/Localization.swift", "top"),
    ("struct ActivityLogLine: Identifiable {", "Model/Models.swift", "top"),
    ("private enum PhoneFrontStyle {", "Workspaces/PhoneMockup.swift", "top"),
    ("struct CardItem: Identifiable, Hashable {", "Model/Models.swift", "top"),
    ("struct KeypadButtonGeometry: Identifiable {", "Model/Keypad.swift", "top"),
    ("// MARK: - View Model", "Model/AppViewModel.swift", "top"),
    ("struct WalletCardView: View {", "Workspaces/CardsWorkspace.swift", "top"),
    ("private enum WorkspaceSection: String, CaseIterable {", "Model/Models.swift", "top"),
    ("private enum FaceLiftPalette {", "App/Theme.swift", "top"),
    ("private struct WalletTileView: View {", "Workspaces/CardsWorkspace.swift", "top"),
    ("struct ContentView: View {", "App/MainWindow.swift", "cvhead"),
    ("    private var walletWorkspace: some View {", "Workspaces/CardsWorkspace.swift", "cv"),
    ("    private var passcodePreview: some View {", "Workspaces/PasscodeWorkspace.swift", "cv"),
    ("    private var walletPhone: some View {", "Workspaces/CardsWorkspace.swift", "cv"),
    ("    private var passcodeWorkspace: some View {", "Workspaces/PasscodeWorkspace.swift", "cv"),
    ("    private var deviceWorkspace: some View {", "Workspaces/DeviceWorkspace.swift", "cv"),
    ("    private var settingsWorkspace: some View {", "App/MainWindow.swift", "cv"),
    ("    private func instructionRow(", "Workspaces/Sheets.swift", "cv"),
    ("    private var workspaceFooter: some View {", "App/MainWindow.swift", "cv"),
    ("    private var guideSheet: some View {", "Workspaces/Sheets.swift", "cv"),
    ("    // MARK: - Floating Chrome (Liquid Glass)", None, "drop"),
    ("    private var scanningNoticeBanner: some View {", "Workspaces/CardsWorkspace.swift", "cv"),
    ("    private var passcodeToolbarView: some View {", "Workspaces/PasscodeWorkspace.swift", "cv"),
    ("    private var activityLogView: some View {", "App/ActivityStatus.swift", "cv"),
    ("    private var bottomBarView: some View {", None, "drop"),
    ("    private var creditsSheet: some View {", "Workspaces/Sheets.swift", "cv"),
    ("    private func openCardImagePicker(for cardId: String) {", "Workspaces/CardsWorkspace.swift", "cv"),
    ("    private func openPasscodeThemePicker() {", "Workspaces/PasscodeWorkspace.swift", "cv"),
    ("// MARK: - App Entry Point", "App/FaceLiftApp.swift", "top"),
]

def find(marker):
    hits = [i for i, l in enumerate(lines) if l == marker or (marker.endswith("(") and l.startswith(marker))]
    assert len(hits) == 1, f"marker {marker!r} matched {len(hits)} lines"
    return hits[0]

starts = sorted((find(m), dest, kind, m) for m, dest, kind in TOP)
assert starts[0][0] <= 5, "first marker must follow the imports"
# ContentView closes on the line just before the entry-point marker's blank run.
entry = find("// MARK: - App Entry Point")
cv_close = max(i for i in range(entry) if lines[i] == "}")

def strip_private(text, member):
    if member:
        text = re.sub(r"(?m)^    ((?:@\w+(?:\([^)]*\))? )*)private ", r"    \1", text)
    else:
        text = re.sub(r"(?m)^(@\w+ )?private (enum|struct|class|func|let|var) ", r"\1\2 ", text)
    return text

out: dict[str, list[str]] = {}
for n, (start, dest, kind, marker) in enumerate(starts):
    end = starts[n + 1][0] if n + 1 < len(starts) else len(lines)
    if kind in ("cv", "drop") and end > cv_close:
        end = cv_close
    chunk = "\n".join(lines[start:end]).rstrip("\n")
    if kind == "drop":
        continue
    if kind == "cvhead":
        chunk = strip_private(chunk, member=True) + "\n}"
    elif kind == "cv":
        chunk = "extension ContentView {\n" + strip_private(chunk, member=True) + "\n}"
    else:
        chunk = strip_private(chunk, member=False)
    out.setdefault(dest, []).append(chunk)

for dest, chunks in out.items():
    path = ROOT / dest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(HEADER + "\n" + "\n\n".join(chunks) + "\n")
    print(f"wrote {dest}")
SRC.unlink()
print("removed FaceLiftApp.swift")
```

- [ ] **Step 4: Run the split**

Run: `mkdir -p build && python3 build/split_ui.py .`
Expected: 13 `wrote …` lines ending with `removed FaceLiftApp.swift`.

- [ ] **Step 5: Point `build.sh` at the new sources**

Replace `build.sh` lines 119–120:

```bash
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target arm64-apple-macosx14.0 FaceLiftApp.swift -o build/FaceLift_arm64
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target x86_64-apple-macosx14.0 FaceLiftApp.swift -o build/FaceLift_x86_64
```

with:

```bash
SWIFT_SOURCES=$(find App Model Workspaces -name '*.swift' | sort)
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target arm64-apple-macosx14.0 $SWIFT_SOURCES -o build/FaceLift_arm64
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target x86_64-apple-macosx14.0 $SWIFT_SOURCES -o build/FaceLift_x86_64
```

- [ ] **Step 6: Verify**

Run the typecheck command. Expected: no output.
Run: `python3 tests/test_localization.py`. Expected: `ok`.
Run: `grep -rn "FaceLiftApp.swift" build.sh Makefile tests .github`. Expected: no matches.

- [ ] **Step 7: Commit**

```bash
git add -A App Model Workspaces FaceLiftApp.swift build.sh tests/test_localization.py
git commit -m "refactor: split FaceLiftApp.swift into App, Model and Workspaces"
```

---

### Task 2: Native window skeleton (split view, toolbar, inspector, status)

Replaces the custom sidebar, 95 pt header, footer and fixed preview pane. The old `FaceLiftApp.swift` scene (hidden title bar, Language menu) stays until Task 3, so the app still builds and language can still be changed.

**Files:**
- Modify: `Model/Models.swift` (replace `enum WorkspaceSection`)
- Create: `Model/AppViewModel+Availability.swift`
- Create: `App/WindowState.swift`, `App/Sidebar.swift`, `App/MainToolbar.swift`
- Replace: `App/MainWindow.swift`, `App/ActivityStatus.swift`
- Modify: `App/Theme.swift` (append brand color)
- Modify: `Workspaces/CardsWorkspace.swift`, `Workspaces/PasscodeWorkspace.swift` (via `build/edit_workspaces.py`)
- Modify: `Resources/en.lproj/Localizable.strings`, `Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: Task 1's `ContentView` members `walletWorkspace`, `walletPreview`, `passcodeWorkspace`, `passcodePreview`, `deviceWorkspace`, `creditsSheet`, `guideSheet`, `addCardSheet`, `openPasscodeThemePicker()`, `openPosterPicker()`, `openBulkImagePicker()`.
- Produces:
  - `enum WorkspaceSection { cards, passcode, creator, device }` with `static let customize: [WorkspaceSection]`, `title: String`, `subtitle: String`, `symbol: String`, `shortcut: KeyEquivalent`, `hasInspector: Bool`.
  - `enum WindowAction { importTheme, choosePoster, setSkinForSelected, flash, restoreDefaultPasscode, refreshDevice, toggleScanning, readSelected, addCardsManually, clearTheme, clearCreator }`.
  - `final class WindowState: ObservableObject` with `section`, `inspectorHidden`, `showGuide`, `showCredits`, `showRestorePasscodeConfirmation`, `pendingAction`, computed `isInspectorPresented: Bool { get set }`, `func send(_ action: WindowAction)`.
  - `AppViewModel` extension: `isBusy`, `isConnected`, `readyToFlashCount`, `hasSelectedCards`, `canScanCards`, `canReadSelected`, `canSetSkinForSelected`, `canFlashCards`, `canFlashPasscode`, `canFlashCreator`, `canRestorePasscode`, `func canFlash(in: WorkspaceSection) -> Bool`.
  - `ContentView.perform(_ action: WindowAction)`, `ContentView.navigate(_:)`.
  - `extension Color { static let brand }`, `func deviceStatusColor(_ device: DeviceInfo?) -> Color`.

- [ ] **Step 1: Add the new interface strings first**

Extra catalog keys are allowed and missing ones fail, so adding every new key now keeps the localization test green through Tasks 2–5.

Append to the end of `Resources/en.lproj/Localizable.strings`:

```
/* Native window shell */
"About FaceLift" = "About FaceLift";
"Cards" = "Cards";
"Change the artwork of your Wallet cards." = "Change the artwork of your Wallet cards.";
"Copy" = "Copy";
"Customize" = "Customize";
"Device" = "Device";
"General" = "General";
"Import .passthm..." = "Import .passthm...";
"Inspector" = "Inspector";
"Lock Screen Themes" = "Lock Screen Themes";
"Model" = "Model";
"More" = "More";
"No activity yet." = "No activity yet.";
"Passcode Cache Cleared" = "Passcode Cache Cleared";
"Passcode Theme Written" = "Passcode Theme Written";
"Restore Default Passcode..." = "Restore Default Passcode...";
"Selection" = "Selection";
"Set Skin for Selected Cards..." = "Set Skin for Selected Cards...";
"Show Activity Log" = "Show Activity Log";
"Show/Hide Inspector" = "Show/Hide Inspector";
"Skins Flashed" = "Skins Flashed";
"iOS Version" = "iOS Version";
```

Append to the end of `Resources/zh-Hans.lproj/Localizable.strings`:

```
/* Native window shell */
"About FaceLift" = "关于 FaceLift";
"Cards" = "卡片";
"Change the artwork of your Wallet cards." = "更换钱包卡片的卡面。";
"Copy" = "拷贝";
"Customize" = "自定义";
"Device" = "设备";
"General" = "通用";
"Import .passthm..." = "导入 .passthm...";
"Inspector" = "检查器";
"Lock Screen Themes" = "锁屏密码主题";
"Model" = "型号";
"More" = "更多";
"No activity yet." = "暂无活动。";
"Passcode Cache Cleared" = "密码缓存已清除";
"Passcode Theme Written" = "密码主题已写入";
"Restore Default Passcode..." = "恢复默认密码键盘...";
"Selection" = "选择";
"Set Skin for Selected Cards..." = "为所选卡片设置卡面...";
"Show Activity Log" = "显示活动日志";
"Show/Hide Inspector" = "显示/隐藏检查器";
"Skins Flashed" = "卡面已写入";
"iOS Version" = "iOS 版本";
```

Run: `python3 tests/test_localization.py` — Expected: `ok`.

- [ ] **Step 2: Replace `WorkspaceSection` in `Model/Models.swift`**

Replace the whole `enum WorkspaceSection: String, CaseIterable { … }` (it has a `.settings` case) with:

```swift
enum WorkspaceSection: String, CaseIterable, Hashable {
    case cards, passcode, creator, device

    /// Sidebar "Customize" group, in display order.
    static let customize: [WorkspaceSection] = [.cards, .passcode, .creator]

    @MainActor var title: String {
        switch self {
        case .cards: return L("Cards")
        case .passcode: return L("Lock Screen Themes")
        case .creator: return L("Theme Creator")
        case .device: return L("Device Connection")
        }
    }

    @MainActor var subtitle: String {
        switch self {
        case .cards: return L("Change the artwork of your Wallet cards.")
        case .passcode: return L("Import, preview and apply a .passthm theme.")
        case .creator: return L("Use a poster or custom images for each key.")
        case .device: return L("Check your iPhone and connection before writing.")
        }
    }

    var symbol: String {
        switch self {
        case .cards: return "creditcard"
        case .passcode: return "lock.iphone"
        case .creator: return "square.grid.3x3"
        case .device: return "iphone"
        }
    }

    /// ⌘1–⌘4 in the View menu.
    var shortcut: KeyEquivalent {
        switch self {
        case .cards: return "1"
        case .passcode: return "2"
        case .creator: return "3"
        case .device: return "4"
        }
    }

    var hasInspector: Bool { self != .device }
}
```

- [ ] **Step 3: Create `Model/AppViewModel+Availability.swift`**

```swift
import SwiftUI

/// Single source of truth for whether an action is available. Toolbar
/// buttons and menu commands both read these, so they never disagree.
extension AppViewModel {
    var isBusy: Bool { isFlashing || isPullingSkins }
    var isConnected: Bool { device?.connected == true }
    var readyToFlashCount: Int { cards.filter { $0.isSelected && $0.customImageURL != nil }.count }
    var hasSelectedCards: Bool { cards.contains(where: \.isSelected) }

    var canScanCards: Bool { isConnected }
    var canReadSelected: Bool { isConnected && device?.isWiFi != true && !isBusy && hasSelectedCards }
    var canSetSkinForSelected: Bool { hasSelectedCards }
    var canFlashCards: Bool { readyToFlashCount > 0 && !isBusy && isConnected }
    var canFlashPasscode: Bool { loadedPasscodeTheme != nil && !isBusy && device?.isUSBConnectedIPhone == true }
    var canFlashCreator: Bool { !effectiveCreatorKeys.isEmpty && !isBusy && device?.isUSBConnectedIPhone == true }
    var canRestorePasscode: Bool {
        device?.isUSBConnectedIPhone == true && device?.passcodeCacheVersion != nil && !isBusy
    }

    func canFlash(in section: WorkspaceSection) -> Bool {
        switch section {
        case .cards: return canFlashCards
        case .passcode: return canFlashPasscode
        case .creator: return canFlashCreator
        case .device: return false
        }
    }
}
```

- [ ] **Step 4: Create `App/WindowState.swift`**

```swift
import SwiftUI

/// Commands that the menu bar and toolbar ask the main window to perform.
/// Actions that need an open panel or window-local state are routed through
/// `WindowState.send(_:)` and handled by `ContentView.perform(_:)`.
enum WindowAction: Equatable {
    case importTheme
    case choosePoster
    case setSkinForSelected
    case flash
    case restoreDefaultPasscode
    case refreshDevice
    case toggleScanning
    case readSelected
    case addCardsManually
    case clearTheme
    case clearCreator
}

/// Window-level UI state shared between the main window and menu commands
/// (published with `focusedSceneObject`).
@MainActor
final class WindowState: ObservableObject {
    @Published var section: WorkspaceSection = .cards
    @Published var inspectorHidden: Set<WorkspaceSection> = []
    @Published var showGuide = false
    @Published var showCredits = false
    @Published var showRestorePasscodeConfirmation = false
    @Published var pendingAction: WindowAction?

    /// Inspector visibility, remembered separately for each page.
    var isInspectorPresented: Bool {
        get { section.hasInspector && !inspectorHidden.contains(section) }
        set {
            if newValue { inspectorHidden.remove(section) } else { inspectorHidden.insert(section) }
        }
    }

    func send(_ action: WindowAction) { pendingAction = action }
}
```

- [ ] **Step 5: Append the brand color to `App/Theme.swift`**

Append at the end of the file:

```swift
// MARK: - Brand color

extension Color {
    /// FaceLift brand accent, tuned separately for light and dark appearance.
    static let brand = Color(nsColor: NSColor(name: "FaceLiftBrand") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4D / 255.0, green: 0x8D / 255.0, blue: 0xFF / 255.0, alpha: 1)
            : NSColor(srgbRed: 0x14 / 255.0, green: 0x66 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
    })
}

/// Green over USB, orange over Wi-Fi, gray when no iPhone is connected.
func deviceStatusColor(_ device: DeviceInfo?) -> Color {
    guard device?.connected == true else { return .gray }
    return device?.isWiFi == true ? .orange : .green
}
```

- [ ] **Step 6: Create `App/Sidebar.swift`**

```swift
import SwiftUI

struct SidebarView: View {
    @ObservedObject var vm: AppViewModel
    @Binding var selection: WorkspaceSection

    var body: some View {
        List(selection: Binding<WorkspaceSection?>(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )) {
            Section(L("Customize")) {
                ForEach(WorkspaceSection.customize, id: \.self) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            Section(L("Device")) {
                DeviceSidebarRow(device: vm.device)
                    .tag(WorkspaceSection.device)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DeviceSidebarRow: View {
    let device: DeviceInfo?

    var body: some View {
        let connected = device?.connected == true
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
                    .foregroundStyle(connected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if connected {
                    Text("iOS \(device?.version ?? "") · \(device?.isWiFi == true ? L("Wi-Fi") : L("USB"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "iphone")
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(deviceStatusColor(device))
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: 2)
                }
        }
    }
}
```

- [ ] **Step 7: Replace `App/ActivityStatus.swift`** (the old `activityLogView` member is superseded by the popover)

```swift
import SwiftUI
import AppKit

/// Toolbar-center status: status text when idle, progress while busy.
/// Clicking it opens the activity log.
struct ActivityStatusView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        Button { vm.showLogs.toggle() } label: {
            HStack(spacing: 8) {
                if vm.isBusy || vm.isCheckingDevice {
                    ProgressView().controlSize(.small)
                } else {
                    Circle()
                        .fill(deviceStatusColor(vm.device))
                        .frame(width: 7, height: 7)
                }
                Text(vm.localizedStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if vm.isFlashing {
                    Text("\(Int(vm.progress * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 180, idealWidth: 320, maxWidth: 420)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Show Activity Log"))
        .popover(isPresented: $vm.showLogs, arrowEdge: .bottom) {
            ActivityLogPopover(vm: vm)
        }
    }
}

struct ActivityLogPopover: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Activity Log")).font(.headline)
                Spacer()
                Button(L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.logs.map(\.display).joined(separator: "\n"), forType: .string)
                }
                .disabled(vm.logs.isEmpty)
                Button(L("Clear")) { vm.logs.removeAll() }
                    .disabled(vm.logs.isEmpty)
            }
            if vm.logs.isEmpty {
                Text(L("No activity yet."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(vm.logs) { line in
                                Text(line.display)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: vm.logs.count) { _, _ in scrollToEnd(proxy) }
                }
            }
        }
        .padding(14)
        .frame(width: 520, height: 320)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = vm.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}
```

- [ ] **Step 8: Replace `App/MainWindow.swift`**

This deletes the custom `sidebar`, `appHeader`, `workspaceTitle`/`workspaceSubtitle`, `settingsWorkspace`, `workspaceFooter`, the gradient background and `.preferredColorScheme(.light)`. `section`, `showGuide` and `showCredits` stay available to workspace code as forwarders onto `WindowState`.

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = AppViewModel()
    @StateObject var window = WindowState()
    @ObservedObject var language = AppLanguage.shared
    @State var cardSearch = ""
    @State var manualHashFeedback = ""
    @State var previewCardIndex = 0
    @State var dragOffsetStart: CGPoint = .zero
    @State var dragKeyStartOffsets: [String: CGPoint] = [:]
    @State var isTargetedPoster = false
    @State var isTargetedTheme = false

    // Forwarders so workspace code keeps reading and writing window state
    // by its original names.
    var section: WorkspaceSection {
        get { window.section }
        nonmutating set { window.section = newValue }
    }
    var showGuide: Bool {
        get { window.showGuide }
        nonmutating set { window.showGuide = newValue }
    }
    var showCredits: Bool {
        get { window.showCredits }
        nonmutating set { window.showCredits = newValue }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm, selection: $window.section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(window.section.title)
                .navigationSubtitle(window.section.subtitle)
                .toolbar { toolbarContent }
                .inspector(isPresented: $window.isInspectorPresented) {
                    inspectorContent
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .tint(Color.brand)
        .focusedSceneObject(vm)
        .focusedSceneObject(window)
        .alert(successTitle, isPresented: $vm.showSuccessAlert) {
            Button(L("OK")) {}
        } message: {
            Text(successMessage)
        }
        .confirmationDialog(L("Restore Default Passcode?"), isPresented: $window.showRestorePasscodeConfirmation) {
            Button(L("Restore Default Passcode"), role: .destructive) { vm.restoreDefaultPasscode() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This backs up and removes the passcode keypad cache for this iOS version. Restart the iPhone afterward so iOS can rebuild its default keypad."))
        }
        .alert(L("Error"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(L("OK")) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $window.showCredits) { creditsSheet }
        .sheet(isPresented: $window.showGuide) { guideSheet }
        .sheet(isPresented: $vm.showAddCardSheet) { addCardSheet }
        .onChange(of: window.section) { _, destination in syncViewModel(to: destination) }
        .onChange(of: window.pendingAction) { _, action in
            guard let action else { return }
            window.pendingAction = nil
            perform(action)
        }
        .onChange(of: vm.selectedTab) { _, newTab in
            if newTab == .passcodeThemes && vm.isScanningCards {
                vm.stopCardScanning()
            }
            vm.dismissScanPrompt()
        }
        .onChange(of: vm.cards.count) { _, count in
            if count == 0 || previewCardIndex >= count { previewCardIndex = 0 }
        }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            if !vm.isFlashing && !vm.isScanningCards && !vm.isPullingSkins {
                vm.checkDevice(silent: true)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch window.section {
        case .cards: walletWorkspace
        case .passcode, .creator: passcodeWorkspace
        case .device: deviceWorkspace
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch window.section {
        case .cards: walletPreview
        case .passcode, .creator: passcodePreview
        case .device: EmptyView()
        }
    }

    private var successTitle: String {
        if vm.didClearPasscodeCache { return L("Passcode Cache Cleared") }
        return vm.selectedTab == .passcodeThemes ? L("Passcode Theme Written") : L("Skins Flashed")
    }

    private var successMessage: String {
        if vm.didClearPasscodeCache {
            return L("Passcode cache cleared. Restart your iPhone to regenerate the default keypad.")
        } else if vm.selectedTab == .passcodeThemes {
            return L("Passcode theme successfully applied!\n\nLock your iPhone to see your new keypad. On iOS 27, restarting may restore the default keypad.")
        }
        return L("Skins successfully applied to all selected cards!\n\nPlease force-close the Wallet app on your iPhone (or reboot) to see your new designs.")
    }

    func navigate(_ destination: WorkspaceSection) {
        window.section = destination
    }

    /// Keeps the view model's tab/mode in step with the sidebar selection.
    private func syncViewModel(to destination: WorkspaceSection) {
        switch destination {
        case .cards, .device:
            vm.selectedTab = .walletCards
        case .passcode:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .applyTheme
        case .creator:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .themeCreator
        }
    }

    func perform(_ action: WindowAction) {
        switch action {
        case .importTheme:
            navigate(.passcode)
            openPasscodeThemePicker()
        case .choosePoster:
            navigate(.creator)
            openPosterPicker()
        case .setSkinForSelected:
            openBulkImagePicker()
        case .flash:
            switch window.section {
            case .cards: vm.applySkin()
            case .passcode: vm.flashPasscodeTheme()
            case .creator: vm.flashCreatedTheme()
            case .device: break
            }
        case .restoreDefaultPasscode:
            window.showRestorePasscodeConfirmation = true
        case .refreshDevice:
            vm.checkDevice()
        case .toggleScanning:
            vm.toggleCardScanning()
        case .readSelected:
            vm.queueSkinPulls(ids: vm.cards.filter(\.isSelected).map(\.id), replacingStored: true)
        case .addCardsManually:
            vm.showAddCardSheet = true
        case .clearTheme:
            vm.loadedPasscodeTheme = nil
        case .clearCreator:
            vm.clearCreator()
        }
    }
}
```

- [ ] **Step 9: Create `App/MainToolbar.swift`**

```swift
import SwiftUI

extension ContentView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ActivityStatusView(vm: vm)
        }
        ToolbarItemGroup(placement: .automatic) {
            pageActions
        }
        ToolbarItemGroup(placement: .primaryAction) {
            primaryActions
            if window.section.hasInspector {
                Button { window.isInspectorPresented.toggle() } label: {
                    Label(L("Inspector"), systemImage: "sidebar.right")
                }
                .help(L("Show/Hide Inspector"))
            }
        }
    }

    @ViewBuilder
    private var pageActions: some View {
        switch window.section {
        case .cards:
            Button { perform(.toggleScanning) } label: {
                Label(vm.isScanningCards ? L("Stop Scanning") : L("Scan Cards"),
                      systemImage: vm.isScanningCards ? "stop.circle" : "wave.3.right")
            }
            .disabled(!vm.canScanCards)
            Button { perform(.addCardsManually) } label: {
                Label(L("Add Manually"), systemImage: "plus")
            }
            Button { perform(.readSelected) } label: {
                Label(L("Read Selected from iPhone"), systemImage: "iphone.and.arrow.forward")
            }
            .disabled(!vm.canReadSelected)
            .help(L("Read artwork for the selected cards only"))
            Button { perform(.setSkinForSelected) } label: {
                Label(L("Set Skin for All..."), systemImage: "photo.on.rectangle.angled")
            }
            .disabled(!vm.canSetSkinForSelected)
            .help(L("Assign one skin to all selected cards"))
        case .passcode:
            Button { perform(.importTheme) } label: {
                Label(L("Choose .passthm File..."), systemImage: "folder.badge.plus")
            }
            targetVersionPicker
        case .creator:
            Button { perform(.choosePoster) } label: {
                Label(vm.creatorPosterImage == nil ? L("Choose Poster...") : L("Change Poster..."), systemImage: "photo")
            }
            targetVersionPicker
        case .device:
            Button { perform(.refreshDevice) } label: {
                Label(L("Refresh device connection"), systemImage: "arrow.clockwise")
            }
            .disabled(vm.isCheckingDevice)
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch window.section {
        case .cards:
            Button { perform(.flash) } label: {
                Label(vm.readyToFlashCount > 0 ? L("Flash Skins (%@ Cards)", "\(vm.readyToFlashCount)") : L("Flash Skins"),
                      systemImage: "sparkles")
            }
            .faceLiftProminentButton()
            .disabled(!vm.canFlashCards)
        case .passcode:
            passcodeMoreMenu(clear: .clearTheme, clearTitle: L("Clear Theme"), clearDisabled: vm.loadedPasscodeTheme == nil)
            Button { perform(.flash) } label: {
                Label(L("Flash Passcode Theme"), systemImage: "lock.shield.fill")
            }
            .faceLiftProminentButton()
            .disabled(!vm.canFlashPasscode)
        case .creator:
            passcodeMoreMenu(clear: .clearCreator, clearTitle: L("Clear All"),
                             clearDisabled: vm.effectiveCreatorKeys.isEmpty && vm.creatorPosterImage == nil)
            Button { perform(.flash) } label: {
                Label(L("Flash to iPhone"), systemImage: "lock.shield.fill")
            }
            .faceLiftProminentButton()
            .disabled(!vm.canFlashCreator)
        case .device:
            EmptyView()
        }
    }

    private var targetVersionPicker: some View {
        Picker(L("Target:"), selection: $vm.targetTelephonyVersion) {
            Text(L("TelephonyUI-10 (iOS 18+)")).tag("TelephonyUI-10")
            Text(L("TelephonyUI-9 (iOS 16–17)")).tag("TelephonyUI-9")
            Text(L("TelephonyUI-8 (iOS 14–15)")).tag("TelephonyUI-8")
            Text(L("Universal (All 8, 9, 10)")).tag("all")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(L("Target:"))
    }

    private func passcodeMoreMenu(clear: WindowAction, clearTitle: String, clearDisabled: Bool) -> some View {
        Menu {
            Button(L("Restore Default Passcode...")) { perform(.restoreDefaultPasscode) }
                .disabled(!vm.canRestorePasscode)
            Divider()
            Button(clearTitle, role: .destructive) { perform(clear) }
                .disabled(clearDisabled)
        } label: {
            Label(L("More"), systemImage: "ellipsis.circle")
        }
        .help(L("More"))
    }
}
```

- [ ] **Step 10: Adapt the pages with `build/edit_workspaces.py`**

Write this script to `build/edit_workspaces.py`:

```python
#!/usr/bin/env python3
"""One-off: adapt the Cards and Lock Screen pages to the native window shell.

- In-page feature cards and toolbar rows go away (sidebar + window toolbar
  replace them); the card search moves to a toolbar search field.
- The previews become inspector content: no page switcher, no floating panel.
- WalletCardView (never instantiated) is deleted.
"""
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def cut_member(src, header):
    """Remove a ContentView member from its header line through its closing '    }'."""
    i = src.index(header)
    j = src.index("\n    }\n", i) + len("\n    }\n")
    return src[:i] + src[j:]


def replace_once(src, old, new):
    assert src.count(old) >= 1, f"not found: {old[:60]!r}"
    return src.replace(old, new, 1)


PAGE_SWITCHER = '''            Picker("", selection: $vm.selectedTab) {
                Text(L("Wallet Cards")).tag(AppTab.walletCards)
                Text(L("Lock Screen")).tag(AppTab.passcodeThemes)
            }
            .pickerStyle(.segmented)
'''
PANEL_CHROME = '''        .padding(17)
        .faceLiftWorkspacePanel(cornerRadius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(FaceLiftPalette.line))
        .shadow(color: FaceLiftPalette.blue.opacity(0.06), radius: 18, y: 6)
'''

# ---- Lock Screen / Creator page
p = ROOT / "Workspaces/PasscodeWorkspace.swift"
s = p.read_text()
head = "    var passcodeWorkspace: some View {"
i = s.index(head)
j = s.index("\n    }\n", i) + len("\n    }\n")
s = s[:i] + '''    var passcodeWorkspace: some View {
        ScrollView {
            passcodeThemeWorkspaceView
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
''' + s[j:]
s = cut_member(s, "    var passcodeToolbarView: some View {")
s = replace_once(s, PAGE_SWITCHER + '''            .onChange(of: vm.selectedTab) { _, tab in if tab == .walletCards { navigate(.cards) } }
''', "")
s = replace_once(s, PANEL_CHROME, "        .padding(16)\n")
p.write_text(s)

# ---- Cards page
p = ROOT / "Workspaces/CardsWorkspace.swift"
s = p.read_text()
start = s.index("                HStack(spacing: 14) {\n                    featureCard(")
end = s.index("                if vm.isScanningCards { scanningNoticeBanner")
s = s[:start] + '''                HStack(spacing: 9) {
                    Text(L("My Cards"))
                        .font(.title3.weight(.semibold))
                    Text("\\(vm.cards.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 4)
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
''' + s[end:]
s = replace_once(s, '''            .padding(.horizontal, 25)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .overlay(alignment: .bottom) { FaceLiftPalette.line.opacity(0.75).frame(height: 1) }
''', '''            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            Divider()
''')
ws_end = s.index("\n    }\n", s.index("    var walletWorkspace: some View {"))
s = s[:ws_end] + '''
        .searchable(text: $cardSearch, placement: .toolbar, prompt: Text(L("Search cards by hash or number")))''' + s[ws_end:]
s = cut_member(s, "    func featureCard(")
s = replace_once(s, PAGE_SWITCHER + '''            .onChange(of: vm.selectedTab) { _, tab in if tab == .passcodeThemes { navigate(.passcode) } }
            .padding(.bottom, 18)
''', "")
s = replace_once(s, PANEL_CHROME, "        .padding(16)\n")
a = s.index("struct WalletCardView: View {")
b = s.index("struct WalletTileView: View {")
s = s[:a] + s[b:]
p.write_text(s)

for name in ("featureCard", "passcodeToolbarView", "WalletCardView"):
    for f in (ROOT / "Workspaces").glob("*.swift"):
        assert name not in f.read_text(), (name, f)
print("workspaces adapted")
```

Run: `python3 build/edit_workspaces.py .`
Expected: `workspaces adapted`

- [ ] **Step 11: Verify**

Run the typecheck command. Expected: no output.
Run: `python3 tests/test_localization.py`. Expected: `ok`.
Run: `grep -rn "featureCard\|passcodeToolbarView\|WalletCardView\|workspaceFooter\|appHeader\|preferredColorScheme" App Workspaces`. Expected: no matches.

- [ ] **Step 12: Commit**

```bash
git add -A App Model Workspaces Resources
git commit -m "feat: adopt NavigationSplitView, window toolbar and inspector"
```

---

### Task 3: Scene, menu commands and Settings window

**Files:**
- Replace: `App/FaceLiftApp.swift`
- Create: `App/AppCommands.swift`, `App/SettingsView.swift`

**Interfaces:**
- Consumes: `WindowState` (`section`, `isInspectorPresented`, `showGuide`, `showCredits`, `send(_:)`), `WindowAction`, `WorkspaceSection.allCases/title/shortcut/hasInspector`, `AppViewModel` `can…` checks and `showLogs`, `isScanningCards`, `isCheckingDevice`, all from Task 2. `ContentView` already calls `.focusedSceneObject(vm)` and `.focusedSceneObject(window)`.
- Produces: `struct FaceLiftCommands: Commands`, `struct SettingsView: View`.

- [ ] **Step 1: Create `App/AppCommands.swift`**

```swift
import SwiftUI

/// Menu bar commands. They act on the focused window through the
/// `WindowState` and `AppViewModel` it publishes with `focusedSceneObject`,
/// and share enablement with the toolbar via `AppViewModel`'s `can…` checks.
struct FaceLiftCommands: Commands {
    @FocusedObject private var vm: AppViewModel?
    @FocusedObject private var window: WindowState?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About FaceLift")) { window?.showCredits = true }
                .disabled(window == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Import .passthm...")) { window?.send(.importTheme) }
                .keyboardShortcut("o")
                .disabled(window == nil)
            Button(L("Choose Poster...")) { window?.send(.choosePoster) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(window?.section != .creator)
            Button(L("Set Skin for Selected Cards...")) { window?.send(.setSkinForSelected) }
                .disabled(window?.section != .cards || vm?.canSetSkinForSelected != true)
        }

        CommandGroup(before: .sidebar) {
            ForEach(WorkspaceSection.allCases, id: \.self) { item in
                Button(item.title) { window?.section = item }
                    .keyboardShortcut(item.shortcut)
                    .disabled(window == nil)
            }
            Divider()
        }

        CommandGroup(after: .sidebar) {
            Button(L("Show/Hide Inspector")) { window?.isInspectorPresented.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(window?.section.hasInspector != true)
            Button(L("Show Activity Log")) { vm?.showLogs.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(vm == nil)
        }

        CommandMenu(L("Device")) {
            Button(L("Refresh device connection")) { window?.send(.refreshDevice) }
                .keyboardShortcut("r")
                .disabled(vm == nil || vm?.isCheckingDevice == true)
            Button(vm?.isScanningCards == true ? L("Stop Scanning") : L("Scan Cards")) {
                window?.section = .cards
                window?.send(.toggleScanning)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(vm?.canScanCards != true)
            Divider()
            Button(L("Flash to iPhone")) { window?.send(.flash) }
                .keyboardShortcut(.return)
                .disabled(window.map { vm?.canFlash(in: $0.section) == true } != true)
            Button(L("Restore Default Passcode...")) { window?.send(.restoreDefaultPasscode) }
                .disabled(vm?.canRestorePasscode != true)
        }

        CommandGroup(replacing: .help) {
            Button(L("FaceLift Guide")) { window?.showGuide = true }
                .keyboardShortcut("?", modifiers: .command)
                .disabled(window == nil)
        }
    }
}
```

- [ ] **Step 2: Create `App/SettingsView.swift`**

```swift
import SwiftUI

/// ⌘, Settings window.
struct SettingsView: View {
    @ObservedObject private var language = AppLanguage.shared

    var body: some View {
        Form {
            Section(L("General")) {
                Picker(L("Language"), selection: $language.choice) {
                    Text(L("Follow System")).tag(AppLanguageChoice.system)
                    Text("English").tag(AppLanguageChoice.en)
                    Text("简体中文").tag(AppLanguageChoice.zhHans)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 3: Replace `App/FaceLiftApp.swift`**

Removes `.windowStyle(.hiddenTitleBar)`, `.windowResizability(.contentSize)` and the custom Language menu (language now lives in Settings).

```swift
import SwiftUI

// MARK: - App Entry Point

@main
struct FaceLiftApp: App {
    @ObservedObject private var language = AppLanguage.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: language.resolved))
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            FaceLiftCommands()
        }

        Settings {
            SettingsView()
                .environment(\.locale, Locale(identifier: language.resolved))
        }
    }
}
```

- [ ] **Step 4: Verify**

Run the typecheck command. Expected: no output.
Run: `python3 tests/test_localization.py`. Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add App/FaceLiftApp.swift App/AppCommands.swift App/SettingsView.swift
git commit -m "feat: add menu commands, keyboard shortcuts and Settings window"
```

---

### Task 4: Device page as a native Form

**Files:**
- Replace: `Workspaces/DeviceWorkspace.swift`

**Interfaces:**
- Consumes: `deviceStatusColor(_:)` (Task 2), `instructionRow(_:_:)` (`Workspaces/Sheets.swift`, Task 1). The refresh button now lives only in the toolbar (Task 2).

- [ ] **Step 1: Replace `Workspaces/DeviceWorkspace.swift`**

```swift
import SwiftUI

extension ContentView {
    var deviceWorkspace: some View {
        let device = vm.device
        let connected = device?.connected == true
        return Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "iphone")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.title3.weight(.semibold))
                        Label(
                            connected ? (device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")) : L("Waiting for device"),
                            systemImage: connected ? "checkmark.circle.fill" : "circle.dotted"
                        )
                        .font(.callout)
                        .foregroundStyle(connected ? deviceStatusColor(device) : Color.secondary)
                    }
                }
                .padding(.vertical, 4)
                if connected {
                    LabeledContent(L("Model"), value: device?.product ?? "iPhone")
                    LabeledContent(L("iOS Version"), value: device?.version ?? "")
                }
            }
            if connected && device?.isWiFi == true {
                Section {
                    Label(L("Reading card artwork requires USB. Reconnect with a cable."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
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
}
```

- [ ] **Step 2: Verify**

Run the typecheck command. Expected: no output.
Run: `python3 tests/test_localization.py`. Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add Workspaces/DeviceWorkspace.swift
git commit -m "feat: restyle the device page as a grouped Form"
```

---

### Task 5: Semantic colors, text styles, no chrome glass

**Files:**
- Modify: all `App/`, `Model/`, `Workspaces/` Swift files touched by `build/restyle_ui.py`
- Temporary: `build/restyle_ui.py`

**Interfaces:**
- Consumes: `Color.brand` (Task 2).
- Produces: `FaceLiftPalette` deleted; `faceLiftDivider`, `faceLiftChrome`, `faceLiftChromeSection`, `faceLiftLogBackground`, `faceLiftWorkspaceChrome` deleted. Kept: `faceLiftPanel`, `faceLiftCapsule`, `faceLiftTintedCapsule`, `faceLiftProminentButton`, `faceLiftSecondaryButton`, `faceLiftGlassGroup`, `faceLiftBannerSurface`, `faceLiftDropZoneFill`, `faceLiftWorkspacePanel`, `KeypadKeySurface`.

- [ ] **Step 1: Write `build/restyle_ui.py`**

```python
#!/usr/bin/env python3
"""One-off: move page UI onto semantic colors and text styles.

- FaceLiftPalette -> semantic colors / brand accent; the enum is deleted.
- Hard-coded light-blue fills -> brand tint.
- .system(size:) -> text styles, only inside page-UI members. The iPhone,
  keypad and card mock renderers keep fixed point sizes on purpose: they
  imitate on-device pixels, not Mac UI text.
- Chrome-only glass helpers that nothing uses any more are deleted.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
FILES = sorted(p for d in ("App", "Model", "Workspaces") for p in (ROOT / d).rglob("*.swift"))

PALETTE = {
    "FaceLiftPalette.ink": "Color.primary",
    "FaceLiftPalette.muted": "Color.secondary",
    "FaceLiftPalette.blue": "Color.brand",
    "FaceLiftPalette.line": "Color(nsColor: .separatorColor)",
    "FaceLiftPalette.surface": "Color(nsColor: .controlBackgroundColor)",
}
LIGHT_FILLS = [
    "Color(red: 0.91, green: 0.94, blue: 0.99)",
    "Color(red: 0.90, green: 0.94, blue: 1)",
    "Color(red: 0.89, green: 0.93, blue: 1)",
]
# Members whose text is Mac UI (restyled). Everything else keeps its sizes.
UI_MEMBERS = {
    "Workspaces/CardsWorkspace.swift": ["struct WalletTileView", "var walletWorkspace", "var walletPreview",
                                        "var scanningNoticeBanner", "var emptyStateView"],
    "Workspaces/PasscodeWorkspace.swift": ["var passcodePreview", "var applyThemeControlsCard",
                                           "var creatorControlsCard", "var targetSettingsCard"],
    "Workspaces/Sheets.swift": ["func instructionRow", "var creditsSheet"],
}
DEAD_HELPERS = ["faceLiftDivider", "faceLiftChrome", "faceLiftChromeSection",
                "faceLiftLogBackground", "faceLiftWorkspaceChrome"]


def style_for(size: int):
    if size <= 10: return "caption"
    if size == 11: return "subheadline"
    if size == 12: return "callout"
    if size == 13: return "body"
    if size <= 15: return "title3"
    if size <= 18: return "title2"
    if size <= 24: return "title"
    if size <= 30: return "largeTitle"
    return None  # large decorative symbols keep their size


FONT = re.compile(r"\.system\(size: (\d+)(?:, weight: \.(\w+))?(?:, design: \.(\w+))?\)")


def restyle_font(m):
    style = style_for(int(m.group(1)))
    if style is None:
        return m.group(0)
    weight, design = m.group(2), m.group(3)
    font = f".system(.{style}, design: .{design})" if design else f".{style}"
    return font + (f".weight(.{weight})" if weight else "")


def member_span(text, header):
    start = text.index(header)
    indent = text[text.rfind("\n", 0, start) + 1:start]
    end = text.index(f"\n{indent}}}\n", start) + len(indent) + 3
    return start, end


for path in FILES:
    rel = path.relative_to(ROOT).as_posix()
    text = path.read_text()
    for old, new in PALETTE.items():
        text = text.replace(old, new)
    for fill in LIGHT_FILLS:
        text = text.replace(fill, "Color.brand.opacity(0.12)")
    for header in UI_MEMBERS.get(rel, []):
        start, end = member_span(text, header)
        text = text[:start] + FONT.sub(restyle_font, text[start:end]) + text[end:]
    if rel == "App/Theme.swift":
        start, end = member_span(text, "enum FaceLiftPalette {")
        text = text[:start] + text[end:]
        for name in DEAD_HELPERS:
            doc = re.compile(r"(?:\n    ///[^\n]*)*\n    @ViewBuilder\n    func " + name + r"\(")
            m = doc.search(text)
            if m:
                s, e = member_span(text, f"func {name}(")
                text = text[:m.start()] + "\n" + text[e:]
        m = re.search(r"@ViewBuilder\nfunc faceLiftDivider\(\) -> some View \{.*?\n\}\n", text, re.S)
        if m:
            text = text[:m.start()] + text[m.end():]
    path.write_text(text)

leftover = [p for p in FILES if "FaceLiftPalette" in p.read_text()]
assert not leftover, leftover
for name in DEAD_HELPERS:
    users = [p for p in FILES if re.search(rf"\b{name}\b", p.read_text())]
    assert not users, (name, users)
print("restyled", len(FILES), "files")
```

- [ ] **Step 2: Run it**

Run: `python3 build/restyle_ui.py .`
Expected: `restyled 19 files` (the script itself asserts that no `FaceLiftPalette` or deleted helper is still referenced).

- [ ] **Step 3: Verify only mock renderers keep fixed sizes**

Run: `grep -rn "\.system(size:" App Workspaces`
Expected: matches only inside `walletPhone`, `applyThemeDialerCanvas`, `creatorButtonView`, `phoneMockupContainer`, plus sizes above 30 pt (`emptyStateView` 54, `applyThemeControlsCard` 32, `creditsSheet` 44). No matches in `App/`.

Run: `grep -rn "Color(red:" App Workspaces`
Expected: only the card-art gradient in `WalletTileView`, the gradient in `walletPhone`, and the phone bezel in `phoneMockupContainer`.

- [ ] **Step 4: Typecheck and localization**

Run the typecheck command. Expected: no output.
Run: `python3 tests/test_localization.py`. Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add -A App Model Workspaces
git commit -m "style: use semantic colors, text styles and native chrome"
```

---

### Task 6: Full build and smoke test

**Files:** none (fixes found here go into a follow-up commit touching only the affected file).

- [ ] **Step 1: Full universal build**

Run: `./build.sh`
Expected: all six stages complete; `build/FaceLift.app` and `build/FaceLift.dmg` exist; no Swift warnings mention files under `App/`, `Model/`, `Workspaces/`.

- [ ] **Step 2: Launch**

Run: `open build/FaceLift.app`

- [ ] **Step 3: Walk the smoke checklist (spec §4). Record pass/fail for each.**

1. System Settings › Appearance: Light, Dark, Auto. Every page readable; no leftover light-only surfaces.
2. Resize to 900×600: sidebar, inspector and toolbar don't overlap; extra toolbar items move to the `»` overflow.
3. Shortcuts: ⌘1–⌘4 switch pages; ⌘O opens the .passthm panel on the Lock Screen page; ⇧⌘O only enabled on Creator; ⌘R refreshes; ⌘↩ flashes only when the page's flash button is enabled; ⌥⌘I toggles the inspector (disabled on Device); ⇧⌘L opens the log popover; ⌘, opens Settings; ⌘? opens the Guide; FaceLift › About FaceLift opens Credits.
4. With no iPhone: sidebar device row shows "No iPhone connected" in gray; Flash buttons and Device › Flash to iPhone are disabled.
5. With an iPhone over USB (user-confirmed on a real device): Scan Cards, Flash Skins, import + Flash Passcode Theme, Restore Default Passcode… all behave as before; success alerts show the new titles; progress shows in the toolbar center.
6. Settings › Language: switching English/简体中文 updates the sidebar, toolbar, menus and Settings. If some text only updates after relaunch, add a caption under the Picker: `Text(L("Some text updates after restarting FaceLift.")).font(.caption).foregroundStyle(.secondary)` plus both catalog entries (zh-Hans: `部分文字需要重新启动 FaceLift 后更新。`), then re-run the localization test.
7. macOS 26: sidebar/toolbar/inspector render as Liquid Glass with no second glass layer behind them. If a macOS 14/15 machine is available, check the Material fallback.

- [ ] **Step 4: Update the README feature line that describes the old chrome**

In `README.md`, the "Liquid Glass UI (macOS 26+)" bullet mentions "a floating glass header, toolbar and status bar". Replace that clause with "a native sidebar, unified toolbar and inspector". Make the equivalent change in `README.zh-CN.md`.

- [ ] **Step 5: Commit**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: describe the native window layout"
```
