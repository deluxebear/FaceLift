import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Liquid Glass Design System
//
// macOS 26+ renders real Liquid Glass surfaces (glassEffect / glassProminent /
// GlassEffectContainer). On macOS 14/15 every helper below falls back to the
// closest classic Material so the deployment target stays at macOS 14.

enum GlassDesign {
    static let supportsGlass: Bool = {
        if #available(macOS 26.0, *) { return true }
        return false
    }()
}

@available(macOS 26.0, *)
func faceLiftGlass(_ tint: Color?, _ interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

@ViewBuilder
func faceLiftDivider() -> some View {
    if #available(macOS 26.0, *) {
        EmptyView()
    } else {
        Divider()
    }
}

extension View {
    /// Floating glass panel (cards, side panels, pills). Falls back to a
    /// translucent control-background fill on older systems.
    @ViewBuilder
    func faceLiftPanel(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: Color = Color(NSColor.controlBackgroundColor).opacity(0.5)
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                faceLiftGlass(tint, interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                fallback,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }

    /// Pill/capsule surface with a Material fallback.
    @ViewBuilder
    func faceLiftCapsule(
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(faceLiftGlass(tint, interactive), in: Capsule())
        } else {
            self.background(fallbackMaterial, in: Capsule())
        }
    }

    /// Tinted accent capsule (version badge) with a solid-color fallback.
    @ViewBuilder
    func faceLiftTintedCapsule(fallback: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(Color.accentColor), in: Capsule())
        } else {
            self.background(fallback, in: Capsule())
        }
    }

    /// Full-width chrome bar. On macOS 26+ the bar is Liquid Glass, so window
    /// content scrolling underneath shows through as a live blur.
    @ViewBuilder
    func faceLiftChrome() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Rectangle())
        } else {
            self
        }
    }

    /// Opaque per-section background, only on pre-Liquid-Glass systems.
    @ViewBuilder
    func faceLiftChromeSection(_ color: NSColor) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.background(Color(color))
        }
    }

    /// Prominent call-to-action button (glass prominent on macOS 26+).
    @ViewBuilder
    func faceLiftProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary button (glass on macOS 26+).
    @ViewBuilder
    func faceLiftSecondaryButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Groups sibling glass shapes so nearby surfaces blend and morph.
    @ViewBuilder
    func faceLiftGlassGroup(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Activity console backdrop: glass on macOS 26+, opaque text background before.
    @ViewBuilder
    func faceLiftLogBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Rectangle())
        } else {
            self.background(Color(NSColor.textBackgroundColor))
        }
    }

    /// Live-scanner banner: tinted glass band on macOS 26+.
    @ViewBuilder
    func faceLiftBannerSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(Color.blue.opacity(0.16)), in: Rectangle())
        } else {
            self.background(Color.blue.opacity(0.1))
        }
    }

    /// Interior fill for dashed drop zones.
    @ViewBuilder
    func faceLiftDropZoneFill(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            Color(NSColor.controlBackgroundColor).opacity(0.4).cornerRadius(cornerRadius)
        }
    }

    /// New workspace surfaces use native Liquid Glass on macOS 26+.
    @ViewBuilder
    func faceLiftWorkspacePanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                faceLiftGlass(tint, false),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func faceLiftWorkspaceChrome() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Rectangle())
        } else {
            self.background(.regularMaterial)
        }
    }
}

/// Translucent keypad key surface: real interactive Liquid Glass on macOS 26+,
/// a white translucent circle on older systems.
struct KeypadKeySurface: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                .glassEffect(Glass.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
        }
    }
}

enum FaceLiftPalette {
    static let ink = Color(red: 0.08, green: 0.13, blue: 0.24)
    static let muted = Color(red: 0.40, green: 0.47, blue: 0.60)
    static let blue = Color(red: 0.08, green: 0.40, blue: 0.95)
    static let line = Color(red: 0.82, green: 0.87, blue: 0.96)
    static let surface = Color.white.opacity(0.88)
}

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
