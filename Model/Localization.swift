import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Interface language

enum AppLanguageChoice: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans = "zh-Hans"

    var id: String { rawValue }
}

@MainActor
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let storageKey = "FaceLift.uiLanguage"

    @Published var choice: AppLanguageChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: Self.storageKey)
            apply(choice)
        }
    }

    @Published private(set) var resolved: String
    private var table: [String: String]

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguageChoice.system.rawValue
        let choice = AppLanguageChoice(rawValue: raw) ?? .system
        self.choice = choice
        let resolved = Self.resolve(choice)
        self.resolved = resolved
        self.table = Self.loadTable(resolved)
    }

    func t(_ key: String, _ args: [String] = []) -> String {
        let template = table[key] ?? key
        guard !args.isEmpty else { return template }
        let arguments: [CVarArg] = args.map { $0 as CVarArg }
        return String(format: template, locale: Locale(identifier: resolved), arguments: arguments)
    }

    private func apply(_ choice: AppLanguageChoice) {
        resolved = Self.resolve(choice)
        table = Self.loadTable(resolved)
    }

    static func resolve(_ choice: AppLanguageChoice) -> String {
        switch choice {
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    static func loadTable(_ code: String) -> [String: String] {
        for url in candidateURLs(code) {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = obj as? [String: String] else { continue }
            return dict
        }
        return [:]
    }

    static func candidateURLs(_ code: String) -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: code
        ) {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("\(code).lproj/Localizable.strings"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("Resources/\(code).lproj/Localizable.strings"))
        return urls
    }
}

@MainActor
func L(_ key: String, _ args: String...) -> String {
    AppLanguage.shared.t(key, args)
}

@MainActor
func L(_ key: String, args: [String]) -> String {
    AppLanguage.shared.t(key, args)
}

@MainActor
func LM(_ key: String) -> Text {
    let raw = L(key)
    if let attributed = try? AttributedString(
        markdown: raw,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return Text(attributed)
    }
    return Text(raw)
}

@MainActor
enum BackendLocalizer {
    struct Rule {
        let regex: NSRegularExpression
        let key: String
    }

    static let rules: [Rule] = [
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Writing (\d+) artwork files \(fast batch\)\.\.\.$"#),
            key: "Writing %@ artwork files (fast batch)..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Invalidating cache \(([^)]+)\)\.\.\.$"#),
            key: "Invalidating cache (%@)..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Failed to update (.+)\.\.\.$"#),
            key: "Failed to update %@..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Successfully updated (.+)\.\.\.$"#),
            key: "Successfully updated %@..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Flashing passcode theme '(.+)' \((\d+) assets\)\.\.\.$"#),
            key: "Flashing passcode theme '%@' (%@ assets)..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^\[Fallback\] Writing (.+) \((\d+)/(\d+)\)\.\.\.$"#),
            key: "[Fallback] Writing %@ (%@/%@)..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Writing (.+) \((\d+)/(\d+)\)\.\.\.$"#),
            key: "Writing %@ (%@/%@)..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Flashing (\d+) asset\(s\) into (.+)\.\.\.$"#),
            key: "Flashing %@ asset(s) into %@..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Batch write notice for (.+), falling back to file-by-file write\.\.\.$"#),
            key: "Batch write notice for %@, falling back to file-by-file write..."
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Could not write (\d+) file\(s\) in ([^:]+): (.+)$"#),
            key: "Could not write %@ file(s) in %@: %@"
        ),
        Rule(
            regex: try! NSRegularExpression(pattern: #"^Passcode theme '(.+)' successfully applied! Lock your iPhone to check\.$"#),
            key: "Passcode theme '%@' successfully applied! Lock your iPhone to check."
        ),
    ]

    static func localize(_ message: String) -> String {
        let range = NSRange(message.startIndex..., in: message)
        for rule in rules {
            guard let match = rule.regex.firstMatch(in: message, range: range) else { continue }
            var args: [String] = []
            for index in 1..<match.numberOfRanges {
                guard let captured = Range(match.range(at: index), in: message) else { continue }
                args.append(String(message[captured]))
            }
            return AppLanguage.shared.t(rule.key, args)
        }
        return L(message)
    }
}

@MainActor
func localizeBackend(_ message: String) -> String {
    BackendLocalizer.localize(message)
}
