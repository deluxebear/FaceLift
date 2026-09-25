import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ActivityLogLine: Identifiable {
    let id = UUID()
    let time: String
    let template: String
    let args: [String]
    let backend: Bool

    @MainActor
    var display: String {
        let body = backend ? localizeBackend(template) : L(template, args: args)
        return "[\(time)] \(body)"
    }
}

// MARK: - Models

struct DeviceInfo: Codable {
    var udid: String?
    var name: String?
    var version: String?
    var product: String?
    var connection: String?
    var language: String?
    var locale: String?
    var bold_text: Bool?
    var airlift_compatible: Bool?
    var connected: Bool
    var error: String?
    
    var isWiFi: Bool { connection == "wifi" }
    var isUSBConnectedIPhone: Bool {
        connected && connection == "usb" && udid != nil && product?.hasPrefix("iPhone") == true
    }
    var passcodeCacheVersion: String? {
        guard let major = Int(version?.split(separator: ".").first ?? "") else { return nil }
        if major >= 18 { return "TelephonyUI-10" }
        if major >= 16 { return "TelephonyUI-9" }
        if major >= 14 { return "TelephonyUI-8" }
        return nil
    }
}

struct CardItem: Identifiable, Hashable {
    let id: String
    var isSelected: Bool = false
    var customImageURL: URL? = nil
    var customImage: NSImage? = nil
    /// The artwork shown is the one FaceLift last put on the iPhone.
    var isOnDevice: Bool = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CardItem, rhs: CardItem) -> Bool {
        lhs.id == rhs.id && lhs.isSelected == rhs.isSelected && lhs.customImageURL == rhs.customImageURL
            && lhs.isOnDevice == rhs.isOnDevice
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case walletCards = "Apple Wallet"
    case passcodeThemes = "Passcode (.passthm)"
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .walletCards: return L("Apple Wallet")
        case .passcodeThemes: return L("Passcode (.passthm)")
        }
    }
}

struct PasscodeThemeInfo: Identifiable {
    var id: String { filePath }
    let name: String
    let filePath: String
    let detectedVersion: String
    let supportedVersions: [String]
    let fileCount: Int
    let keysPreview: [String: NSImage]
}

enum PasscodeTabMode: String, CaseIterable, Identifiable {
    case applyTheme = "Apply .passthm"
    case themeCreator = "Theme Creator"
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .applyTheme: return L("Apply .passthm")
        case .themeCreator: return L("Theme Creator")
        }
    }
}

enum CreatorSubMode: String, CaseIterable, Identifiable {
    case posterSlice = "Poster Slice (Puzzle)"
    case individualKeys = "Individual Keys"
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .posterSlice: return L("Poster Slice (Puzzle)")
        case .individualKeys: return L("Individual Keys")
        }
    }
}

enum PasscodeLanguageTarget: String, CaseIterable, Identifiable {
    case all = "All Languages (Universal)"
    case uk = "Ukrainian (uk)"
    case ru = "Russian (ru)"
    case en = "English (en)"
    case other = "Other / Fallback"
    case es = "Spanish (es)"
    case de = "German (de)"
    case fr = "French (fr)"
    case pl = "Polish (pl)"
    case nl = "Dutch (nl)"
    case it = "Italian (it)"
    case pt = "Portuguese (pt)"
    case tr = "Turkish (tr)"
    case ja = "Japanese (ja)"
    case ko = "Korean (ko)"
    case zh = "Chinese (zh)"
    case ar = "Arabic (ar)"
    case he = "Hebrew (he)"
    
    var id: String { rawValue }

    @MainActor var title: String { L(rawValue) }

    static var macOSPreferred: Self {
        guard let identifier = Locale.preferredLanguages.first else { return .all }
        return forLanguageIdentifier(identifier)
    }

    static func forLanguageIdentifier(_ identifier: String) -> Self {
        let language = identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { String($0).lowercased() } ?? ""
        switch language {
        case "uk": return .uk
        case "ru": return .ru
        case "en": return .en
        case "es": return .es
        case "de": return .de
        case "fr": return .fr
        case "pl": return .pl
        case "nl": return .nl
        case "it": return .it
        case "pt": return .pt
        case "tr": return .tr
        case "ja": return .ja
        case "ko": return .ko
        case "zh": return .zh
        case "ar": return .ar
        case "he": return .he
        default: return .other
        }
    }
    
    var code: String {
        switch self {
        case .all: return "all"
        case .uk: return "uk"
        case .ru: return "ru"
        case .en: return "en"
        case .other: return "other"
        case .es: return "es"
        case .de: return "de"
        case .fr: return "fr"
        case .pl: return "pl"
        case .nl: return "nl"
        case .it: return "it"
        case .pt: return "pt"
        case .tr: return "tr"
        case .ja: return "ja"
        case .ko: return "ko"
        case .zh: return "zh"
        case .ar: return "ar"
        case .he: return "he"
        }
    }
}

enum PasscodeBoldTarget: String, CaseIterable, Identifiable {
    case both = "Universal (Regular + Bold)"
    case boldOnly = "Bold Text Only (Fast)"
    case regularOnly = "Regular Font Only (Fast)"
    
    var id: String { rawValue }

    @MainActor var title: String { L(rawValue) }
    
    var code: String {
        switch self {
        case .both: return "both"
        case .boldOnly: return "bold"
        case .regularOnly: return "regular"
        }
    }
}

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
