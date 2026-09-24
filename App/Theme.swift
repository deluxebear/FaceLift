import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AppAppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "FaceLift.appearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A dark, nearly transparent key surface keeps the white labels legible
/// without covering the lock-screen artwork with opaque glass discs.
struct KeypadKeySurface: View {
    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.16))
            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
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

    /// Opaque navigation sidebar surface, including the area below its rows.
    static let sidePanelBackground = Color(nsColor: NSColor(name: "FaceLiftSidePanelBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x22 / 255.0, green: 0x23 / 255.0, blue: 0x27 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xF7 / 255.0, green: 0xF8 / 255.0, blue: 0xFA / 255.0, alpha: 1)
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
