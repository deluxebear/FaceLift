# Page Content Redesign — Design

Date: 2026-09-24
Status: Approved in brainstorming, pending spec review

## Context

Sub-project 1 (`2026-09-23-native-window-shell-design.md`) replaced the window
skeleton with native macOS structure: `NavigationSplitView`, window toolbar,
`.inspector`, menu commands and a Settings scene. Page contents were moved
as-is and still use custom glass panels, hand-built drop zones, many
glass/prominent buttons and labels stacked above controls.

This spec redesigns the **visual style and layout inside every page** (Cards,
Lock Screen Themes, Theme Creator, Device) and the three sheets. It takes the
place of the visual part of sub-projects 2–4.

## Goal and constraints

- Every page reads like a first-party Mac app (System Settings, Photos,
  Keynote): clear hierarchy, native controls, correct in Light and Dark Mode.
- **Interactions stay the same.** Existing actions, gestures, drop targets
  and flows keep working. Only placement and appearance change. The two
  additions are a card context menu (mirrors the existing `⋯` menu) and an
  Export command (`⌘E`, already existing function).
- Out of scope: sidebar, toolbar (except the Export button), menus (except
  File ▸ Export), Settings window, activity status, device communication and
  flash logic.

## 1. Shared visual rules

**No glass on content.** Delete `faceLiftWorkspacePanel`, `faceLiftPanel`,
`faceLiftDropZoneFill`, `faceLiftBannerSurface`, `faceLiftCapsule` and
`faceLiftTintedCapsule` from `App/Theme.swift`. Settings-like content uses
`Form` with `.formStyle(.grouped)`. Liquid Glass stays only on the simulated
iOS keypad keys (`KeypadKeySurface`, `faceLiftGlassGroup`).

**Button hierarchy.** One prominent button per page: the toolbar's Flash
action. In-page buttons use `.bordered` or `.borderless`; delete
`faceLiftProminentButton` and `faceLiftSecondaryButton`. The only in-page
`.borderedProminent` is the primary action of an empty state. Secondary
actions (Remove, Reset, examples) go into a `⋯` `Menu` or a context menu.

**Type and spacing.** No large in-page titles (the window title names the
page). Section titles come from `Form`/`Section` or `.headline`; explanatory
text is `.callout`/`.caption` in `.secondary`. Spacing on an 8 pt grid,
20 pt content inset. Strokes use `Color(nsColor: .separatorColor)`. The
accent color marks only selection and links; no tinted accent fills.

**Status.** Warnings show an orange icon with `.primary` text. In-page
notices (scanning, hidden selection) share one `NoticeBar` view: an
`HStack` on `Color(nsColor: .controlBackgroundColor)` with an 8 pt rounded
separator stroke.

**Inspector.** No "Live Preview" `.title2` header anywhere.

## 2. Cards page

**Control row** (one line, `Divider` below):
- Leading: `.secondary` text "5 cards · 3 selected" (replaces "My Cards" +
  count badge).
- Trailing: existing `CardSearchField` and Selection menu, unchanged.

**Card tile** (`WalletTileView`), Photos-style:
- No panel, glass, border or shadow around the tile. The artwork is the
  thumbnail: aspect 1.59, 10 pt continuous corner radius.
- Row below: `Toggle` with `.toggleStyle(.checkbox)` bound to `isSelected`
  (keeps the existing accessibility label/value/hint), "Card #1" in
  `.headline`, status ("Artwork ready"/"Artwork not set") in `.caption`
  `.secondary`, trailing `Menu` with `ellipsis.circle`,
  `.menuStyle(.borderlessButton)`, `.menuIndicator(.hidden)`.
- Selected: 3 pt accent stroke outside the artwork and a
  `checkmark.circle.fill` badge top-trailing.
- Drop targeted (`isTargeted`): accent stroke on the artwork.
- No artwork: neutral placeholder (`.quaternary` fill) with
  `photo.badge.plus`, "Add Artwork" and a monospaced hash fragment, replacing
  the blue gradient card. Tapping it still opens the picker.
- `.contextMenu` on the tile with the same items as the `⋯` menu (one shared
  `@ViewBuilder`).

**Grid.** Keep `walletGridColumns(for:)` column math (tied to the inspector
width); set grid spacing to 16 pt.

**Removed.** The "Make a passcode theme / Open Creator" banner.

**Scanning.** `NoticeBar` at the top of the list: small `ProgressView`,
"Live Scanner Active", the instruction line in `.caption`, trailing
`.controlSize(.small)` "Done". The hidden-selection warning uses `NoticeBar`
too.

**Empty state.** `ContentUnavailableView` titled "No Cards Yet", description
with the three steps, actions "Start Scanning" (`.borderedProminent`,
disabled without a connected iPhone) and "Add Hashes Manually" (`.bordered`).

**Inspector.** Wallet phone mockup and page dots unchanged; header removed.

## 3. Lock Screen Themes and Theme Creator (canvas + inspector)

**Layout** (both pages)
- Detail area = `ThemeCanvas`: the phone mockup centered on
  `Color(nsColor: .underPageBackgroundColor)`. `phoneMockupContainer` scales
  to fit with the maximum raised from 1.0 to 1.25. A `.caption` `.secondary`
  line under the phone: "Previewing at <device name> size" (or "iPhone
  Preview" without a device).
- Drops move to the whole canvas: `.passthm` on Lock Screen, poster images
  on Creator. While targeted the canvas shows an accent inset stroke.
- Per-key drag, tap-to-select, per-key drop and key context menus are
  unchanged.
- Inspector = page parameters as `Form(.grouped)`, same width rule as today.
  Theme pages default to inspector shown; per-page visibility memory
  (`WindowState.inspectorHidden`) is unchanged.
- `MainWindow.detail` and `inspectorContent` switch per section:
  `.passcode`/`.creator` → `themeCanvas` in detail, `applyThemeInspector` /
  `creatorInspector` in the inspector. `passcodePreview` is deleted.

**Lock Screen inspector**
- Section "Theme File":
  - Loaded: row with `lock.square.stack.fill`, theme name (`.headline`),
    supported versions and "N artwork assets" (`.caption` `.secondary`);
    below it an "Edit in Creator" `.bordered` button.
  - Not loaded: "No theme selected" (`.secondary`) and a "Choose File…"
    button. The canvas shows "Drop a .passthm file here" under the phone.
  - "Change…"/"Clear" are not repeated here (toolbar, ⌘O, toolbar `⋯`).
- Section "Flash Target" (shared `flashTargetSection`): `Picker` "Keyboard
  Language" and `Picker` "Font Weight" with `.pickerStyle(.menu)`, labels
  leading; the universal/fast-mode hint becomes the section footer.
- Removed: the dashed full-width drop zone and the inspector's bottom
  "Choose .passthm File…" button.

**Creator inspector**
- Top: `Picker` Poster Slice / Individual Keys, `.segmented`,
  `.labelsHidden()`.
- Poster Slice:
  - Section "Poster": thumbnail (40×52), "Artwork Loaded", "Change…"
    `.bordered`, trailing `⋯` menu with "Use Chinese Numeral Example" and
    "Remove". Empty: "Choose Image…" `.bordered` plus "Use Chinese Numeral
    Example" as `.link`.
  - Section "Slicing Style": segmented Seamless Poster / Circle Buttons,
    `.labelsHidden()`, description as footer.
  - Section "Framing": header with trailing borderless "Reset"; row with
    zoom `Slider` between magnifier icons and "1.0x" in
    `.monospacedDigit()`; footer "Drag on the preview to reposition".
- Individual Keys:
  - Section "Keys": `LabeledContent` "Configured" "3 / 10"; "Fill from
    Poster" (when slices exist) and "Clear All Keys" `.bordered`; footer
    with the click/drag/drop hint.
  - Section "Key 5" (only while a key with an image is selected): header
    with trailing "Done" (deselects); zoom slider row; drag hint;
    "Change Image…", "Reset", "Remove" at `.controlSize(.small)`.
- Section "Flash Target": shared with Lock Screen.
- **Export .passthm** moves from the inspector's bottom button to a toolbar
  `square.and.arrow.up` button on the Creator page and a File ▸ "Export
  .passthm…" (⌘E) command, both via a new `WindowAction.exportTheme`,
  disabled when `vm.effectiveCreatorKeys.isEmpty`.

**File split.** `Workspaces/PasscodeWorkspace.swift` (1028 lines) becomes:
- `ThemeCanvas.swift`: canvas, `phoneMockupContainer`, both dialer canvases,
  `creatorButtonView`.
- `ApplyThemeInspector.swift`: Lock Screen inspector and
  `flashTargetSection`.
- `CreatorInspector.swift`: Creator inspector.
- `PasscodeWorkspace.swift` keeps open/save panels and drop/image loading
  helpers.

## 4. Device page

- Header row: `iphone` symbol with a status dot (same colors as the
  sidebar), device name in `.title3`, subtitle "iOS 27.0 · Connected via
  Wi-Fi" in `.secondary`. Disconnected: "No iPhone connected" /
  "Waiting for device".
- `LabeledContent` rows: Model, iOS Version, Connection.
- Wi-Fi warning in its own section: orange icon, `.primary` text.
- "How to connect" keeps three steps; `instructionRow` numbers become
  `.secondary` on a `.quaternary` circle.

## 5. Sheets

Shared: buttons bottom-trailing, primary `.keyboardShortcut(.defaultAction)`,
cancel `.keyboardShortcut(.cancelAction)`, system button styles, titles in
`.headline`.

- **Guide:** no top "Close". Steps grouped under "Cards" (1–3) and "Lock
  Screen Themes" (4–5) subheadings; "Done" bottom-trailing.
- **About (Credits):** `NSApp.applicationIconImage` at 64 pt, name, version
  from `CFBundleShortVersionString`, one-line tagline; credits in a two-column
  `Grid` (labels trailing-aligned `.secondary`, values leading) without the
  colored leading icons; "Done".
- **Add Card Hashes:** explanation as plain `.secondary` text (no tinted
  box); `TextEditor` with a system-style border; "Cancel" and "Add to List"
  (default action) bottom-trailing. Feedback text unchanged.

## 6. Verification

**Automated**
- `./build.sh` succeeds for arm64 and x86_64 with no new warnings.
- `pytest tests/` passes, including the localization scan; every new
  string has en and zh-Hans entries.

**Screenshots.** Launch the build, switch pages with ⌘1–⌘4 and capture the
window with `screencapture -l<window id>`, in Light and Dark, at 900×600
and a large window, and compare with the pre-change captures.

**Manual checklist**
1. Cards: checkbox selection, search with the hidden-selection notice, drop
   artwork, `⋯` and context menus, empty state, scanning notice.
2. Creator: poster drag, key tap/select, key drop, key context menu, zoom,
   Reset, Export via toolbar and ⌘E.
3. Lock Screen: drop .passthm on the canvas, ⌘O, Edit in Creator.
4. ⌥⌘I hides/shows the inspector per page.
5. Sheets: Return/Esc trigger the right buttons.
6. Flashing to a real iPhone (logic untouched): one spot check by the user.

## Commit sequence

1. Shared visual rules (`Theme.swift`, `NoticeBar`).
2. Cards page.
3. Split `PasscodeWorkspace.swift` with no logic changes.
4. Theme pages canvas + inspector, Export command.
5. Device page and sheets.

## Risks

- **Canvas scaling blurs raster previews** above 1.0: cap at 1.25 and check
  key images visually.
- **Controls hidden with the inspector** on theme pages: accepted, matches
  Keynote; ⌥⌘I and the toolbar toggle restore it.
- **Drop target moved** from the page to the canvas: the canvas fills the
  detail area, so the drop area does not shrink.
