import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Liquid Glass Design System
//
// Page content uses system styles; Liquid Glass is kept only for the simulated
// iOS keypad. macOS 26+ renders real glass (glassEffect / GlassEffectContainer);
// macOS 14/15 fall back to translucent fills so the deployment target stays 14.

enum GlassDesign {
    static let supportsGlass: Bool = {
        if #available(macOS 26.0, *) { return true }
        return false
    }()
}

extension View {
    /// Groups sibling glass shapes so nearby surfaces blend and morph.
    @ViewBuilder
    func faceLiftGlassGroup(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
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
