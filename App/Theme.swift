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

    /// Live-scanner banner: tinted glass band on macOS 26+.
    @ViewBuilder
    func faceLiftBannerSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(Color.brand.opacity(0.16)), in: Rectangle())
        } else {
            self.background(Color.brand.opacity(0.1))
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
