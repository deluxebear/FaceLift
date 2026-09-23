# Native macOS Window Shell — Design (Sub-project 1 of 4)

Date: 2026-09-23
Status: Approved in brainstorming, pending spec review

## Context

The macOS UI redesign (scope "C": native structure plus per-page interaction
redesign) is split into four sub-projects, each with its own spec, plan and
implementation:

| # | Sub-project | Depends on |
|---|---|---|
| **1** | **Native window shell (this spec)** | — |
| 2 | Card management interaction | 1 |
| 3 | Passcode theme apply interaction | 1 |
| 4 | Theme creator interaction | 1, 3 |

The current UI (`FaceLiftApp.swift`, ~5000 lines) deviates from the macOS HIG:
a hand-built `HStack` sidebar at a fixed 218 pt, `.hiddenTitleBar` with a
custom 95 pt header, primary actions in a custom footer, a fixed 332 pt
preview pane instead of an inspector, Settings as a sidebar page, forced
light mode, a hard-coded RGB palette and gradient background, hard-coded
font sizes, duplicated device status (sidebar and header), Guide and Help
buttons opening the same sheet, and only a custom "Language" menu.

## Goal

Replace the window skeleton with native macOS structure: `NavigationSplitView`,
a native toolbar, `.inspector`, a `Settings` scene, menu commands, semantic
colors, text styles and Dark Mode. Page contents keep their current
controls and interactions (only colors, fonts and the relocation of
chrome-level buttons change). Per-page interaction redesign is out of scope
and belongs to sub-projects 2–4.

## 1. File structure and build

`FaceLiftApp.swift` is split and removed:

```
App/
  FaceLiftApp.swift      @main, WindowGroup, Settings scene, commands wiring
  MainWindow.swift       NavigationSplitView + toolbar + inspector + global alerts/sheets
  Sidebar.swift          two-group sidebar + device row
  ActivityStatus.swift   toolbar-center status/progress view + log popover
  AppCommands.swift      menu commands (via focusedSceneValue)
  SettingsView.swift     ⌘, Settings window (language)
  Theme.swift            brand accent (dynamic NSColor), GlassDesign modifiers
Model/
  AppViewModel.swift     existing AppViewModel, minimal changes
  Models.swift           DeviceInfo, CardItem, enums
  Localization.swift     AppLanguage, L()/LM(), BackendLocalizer
  Keypad.swift           KeypadLayout, KeypadSlicer, PasscodeThemeExporter
Workspaces/
  CardsWorkspace.swift   card page + card preview, moved as-is
  PasscodeWorkspace.swift apply + creator + keypad preview, moved as-is
  DeviceWorkspace.swift  device detail page (restyled as native Form)
  Sheets.swift           Guide / Credits / Add Card sheets
```

- `build.sh` compiles `$(find App Model Workspaces -name '*.swift')` for both
  targets; deployment target stays macOS 14 (`NavigationSplitView` 13+,
  `.inspector` 14+).
- `tests/test_localization.py` scans all `.swift` files under those three
  directories instead of the single file.
- Delete dead code: `topChrome`, `headerView` (defined, never used) and the
  in-page `featureCard` navigation cards (redundant with the sidebar).
- Visibility: members that were `private` inside one file and are now used
  across files become `internal`; change only what the compiler requires.

## 2. Window layout and toolbar

**Window**
- Remove `.hiddenTitleBar`; use `.windowToolbarStyle(.unified)`.
  `navigationTitle` shows the page name, `navigationSubtitle` a short
  description (replacing the custom header).
- Minimum window 900×600 (was 1120×760). Sidebar column width 180–260
  (ideal 210); inspector column width 280–400 (ideal 320).
- Remove `.preferredColorScheme(.light)` and the gradient background.

**Sidebar** — `List(selection:)` with `.listStyle(.sidebar)`
- Section "Customize": Cards (`creditcard`), Lock Screen Themes
  (`lock.iphone`), Theme Creator (`square.grid.3x3`).
- Section "Device": one row for the iPhone showing name, `iOS x · USB/Wi-Fi`
  and a status dot (green USB, orange Wi-Fi, gray disconnected);
  "No iPhone connected" in secondary style when absent. Selecting it opens
  the device page.
- Remove the large logo block. The header's device button is removed.
- `WorkspaceSection.settings` is removed; `.passcode` and `.creator` remain
  separate sidebar items and keep `vm.passcodeTabMode` in sync as today.

**Inspector** — `.inspector(isPresented:)`
- Cards: card preview. Lock Screen and Creator: keypad preview. Device: none.
- Toggle button (`sidebar.right`) at the trailing end of the toolbar, ⌥⌘I.
  Visibility remembered per page.

**Toolbar per page** (the in-page toolbar rows are removed; their buttons
move to the window toolbar)

| Page | Page actions | `.primaryAction` |
|---|---|---|
| Cards | Scan Cards (toggle), Add Manually, Read Selected from iPhone, Set Skin for All…; `.searchable` card search | **Flash Skins (N)**, prominent |
| Lock Screen | Choose .passthm…, target version Picker | **Flash Passcode Theme**; `⋯` menu: Restore Default Passcode…, Clear Theme (unloads the .passthm) |
| Creator | Choose Poster…, target version Picker | **Flash to iPhone**; `⋯` menu: Restore Default Passcode…, Clear All (`vm.clearCreator()`) |
| Device | Refresh Connection | — |

List-scoped actions (Select All / Deselect All / Clear All) move to a small
control row above the card list; their redesign belongs to sub-project 2.

**Activity status** (toolbar `.principal`)
- Idle: secondary status text (`vm.localizedStatus`) with status dot.
- Busy (flashing / reading): small progress indicator, percentage, current step.
- Click opens a log popover: monospaced, selectable, with Copy and Clear.
- The footer bar and its "Log" button are removed.

## 3. Menus, Settings and feedback

Page actions reach menus through `focusedSceneValue` (view model + current
section). Enablement conditions live in view-model computed properties
(`canFlashCards`, `canFlashPasscode`, `canFlashCreator`, `canRestorePasscode`,
`canScanCards`, `canReadSelected`) shared by toolbar buttons and menu items.

| Menu | Items |
|---|---|
| FaceLift | About FaceLift (replaces `.appInfo`, opens the existing Credits content); Settings… (⌘,) |
| File | Import .passthm… (⌘O); Choose Poster… (⇧⌘O, Creator only); Set Skin for Selected Cards… |
| View | Cards / Lock Screen Themes / Theme Creator / Device (⌘1–⌘4); Show/Hide Inspector (⌥⌘I); Show Activity Log (⇧⌘L); system sidebar toggle |
| Device (new) | Refresh Connection (⌘R); Start/Stop Scanning Cards (⇧⌘S); Flash to iPhone (⌘↩, page-dependent); Restore Default Passcode… |
| Help | FaceLift Guide (⌘?, opens existing Guide content) |

- The custom top-level "Language" menu is removed.
- Header Guide/Help buttons and header `⋯` menu are removed.

**Settings scene** — `Settings { SettingsView() }`, `Form` with
`.formStyle(.grouped)`; "General" section with the interface language Picker
(Follow System / English / 简体中文). A "takes effect after restart" note is
shown only if verified necessary during implementation.

**Feedback**
- Success results that require action on the iPhone stay alerts with
  specific, localized titles ("Skins Flashed", "Passcode Theme Written") and
  next-step text; the iOS 27 reboot caveat stays in the passcode message.
- Error alert unchanged except for a localized title.
- Restore confirmation stays a `confirmationDialog` with a destructive button.
- Transient results (e.g. artwork read complete) appear only in the activity
  status, not as alerts.

**Visual system** (`Theme.swift`)
- Brand accent: dynamic `NSColor`, light `#1466F2`, dark `#4D8DFF`, applied
  with `.tint()` at the root; drives prominent buttons and selection.
- Delete `FaceLiftPalette`: `ink` → `.primary`, `muted` → `.secondary`,
  `line` → `Divider`/`.separator`, `surface` → `.background` or material,
  `blue` → accent.
- Replace hard-coded `.system(size:)` with text styles (`.title2`,
  `.headline`, `.body`, `.callout`, `.caption`).
- Keep `GlassDesign`. Native sidebar, toolbar and inspector get Liquid Glass
  automatically on macOS 26, so remove manual glass from chrome
  (`faceLiftWorkspaceChrome` and similar) and keep it only on content cards
  and keypad keys to avoid double glass.

## 4. Verification

**Automated**
- `./build.sh` succeeds for arm64 and x86_64 with no new warnings.
- `pytest tests/` passes, including the multi-directory localization scan.
  All new strings have en and zh-Hans entries.

**Manual smoke checklist**
1. Light, Dark and system appearance: no unreadable text or leftover
   hard-coded colors on any page.
2. At 900×600, sidebar, inspector and toolbar do not overlap; toolbar
   overflow collapses into the overflow menu.
3. ⌘1–4, ⌘O, ⌘R, ⌘↩, ⌥⌘I, ⇧⌘L, ⌘, work and are disabled when unavailable.
4. No iPhone: sidebar device row is gray; flash actions and commands disabled.
5. With iPhone (real device, user-confirmed): card scan, skin flash, .passthm
   import + flash and restore default behave as before the refactor.
6. Switching English/简体中文 updates menus, toolbar and Settings.
7. macOS 26 shows Liquid Glass without double glass; if available, check
   the Material fallback on macOS 14/15.

## Risks

- **Regression while moving code:** first commit is a pure file split with no
  logic changes, verified by build and tests; layout changes follow in
  separate commits for easy bisection.
- **`private` visibility across files:** widen only as the compiler requires.
- **Toolbar/menu enablement drift:** single source of truth in view-model
  computed properties.

## Out of scope

- Interaction redesign inside the Cards, Lock Screen and Creator pages
  (sub-projects 2–4).
- Changes to the device communication backend or passcode write behavior.
