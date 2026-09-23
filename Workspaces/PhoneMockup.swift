import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum PhoneFrontStyle {
    case dynamicIsland, notch, homeButton
}

/// Device ProductType comes from device_helper; unknown models use a modern
/// iPhone outline until Apple publishes their exact front geometry.
struct PhonePreviewProfile {
    let front: PhoneFrontStyle
    let aspectRatio: CGFloat
    let maxWidth: CGFloat
    let cornerRadius: CGFloat

    static func forDevice(_ device: DeviceInfo?) -> PhonePreviewProfile {
        let product = (device?.product ?? "").lowercased()
        let name = (device?.name ?? "").lowercased()
        let generation = Int(product.dropFirst("iphone".count).split(separator: ",").first ?? "") ?? 0
        let isSE = ["iphone8,4", "iphone12,8", "iphone14,6"].contains(product)
            || name.contains("iphone se")
        let isNotch = product == "iphone17,5" || name.contains("16e") || name.contains("17e")
            || (generation > 0 && generation < 15)
        let isLarge = name.contains("max") || name.contains("plus")
            || ["iphone15,3", "iphone15,5", "iphone16,2", "iphone17,2", "iphone17,4"].contains(product)
        let isMini = name.contains("mini") || ["iphone13,1", "iphone14,4"].contains(product)

        if isSE {
            return PhonePreviewProfile(front: .homeButton, aspectRatio: 1.78, maxWidth: 244, cornerRadius: 25)
        }
        return PhonePreviewProfile(
            front: isNotch ? .notch : .dynamicIsland,
            aspectRatio: isLarge ? 2.16 : 2.12,
            maxWidth: isLarge ? 280 : (isMini ? 248 : 266),
            cornerRadius: 37
        )
    }
}

struct PhoneFrameChrome: ViewModifier {
    let profile: PhonePreviewProfile

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: profile.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: profile.cornerRadius, style: .continuous)
                    .stroke(Color.gray.opacity(0.85), lineWidth: 3)
            )
            .overlay(alignment: .top) {
                Group {
                    switch profile.front {
                    case .dynamicIsland:
                        Capsule()
                            .fill(.black)
                            .frame(width: 70, height: 20)
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                            .padding(.top, 10)
                    case .notch:
                        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                            .fill(.black)
                            .frame(width: 112, height: 27)
                            .overlay(alignment: .bottom) {
                                Capsule().fill(Color.gray.opacity(0.55)).frame(width: 35, height: 3).padding(.bottom, 8)
                            }
                    case .homeButton:
                        HStack(spacing: 8) {
                            Circle().fill(Color.gray.opacity(0.55)).frame(width: 6, height: 6)
                            Capsule().fill(Color.gray.opacity(0.55)).frame(width: 38, height: 4)
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if profile.front == .homeButton {
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                        .frame(width: 28, height: 28)
                        .padding(.bottom, 10)
                } else {
                    Capsule().fill(.white).frame(width: 90, height: 4).padding(.bottom, 10)
                }
            }
            .overlay(alignment: .trailing) {
                Capsule().fill(Color.gray.opacity(0.8)).frame(width: 3, height: 50).offset(x: 2, y: -96)
            }
            .shadow(color: .black.opacity(0.20), radius: 13, y: 7)
    }
}
