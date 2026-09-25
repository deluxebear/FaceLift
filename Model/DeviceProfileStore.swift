import Foundation

// Per-iPhone storage. The layout matches device_profiles.py, which the
// backend uses to check that a card belongs to the iPhone it writes to:
//
//   devices.json                        known iPhones
//   Devices/<udid>/profile.json         that iPhone's cards
//   Devices/<udid>/skins/<hash>.png     artwork shown for each card
//   Devices/<udid>/originals/<hash>/    artwork captured before the first change
//   Devices/<udid>/history/<hash>/      artwork FaceLift has written
//   Legacy/                             pre-profile cards.json and skins/

struct DeviceRecord: Codable, Identifiable, Equatable {
    let udid: String
    var name: String?
    var customName: String?
    var product: String?
    var lastVersion: String?
    var firstSeen: String?
    var lastSeen: String?

    var id: String { udid }
    var displayName: String { customName ?? name ?? "iPhone" }
}

struct DeviceIndex: Codable {
    var schema: Int?
    var lastActiveUDID: String?
    var legacyPromptDismissed: Bool?
    var devices: [DeviceRecord]?
}

struct StoredCard: Codable {
    let id: String
    var addedAt: String?
    var source: String?
}

struct PasscodeRecord: Codable {
    var lastAppliedTheme: String?
    var lastAppliedVersion: String?
    var lastAppliedAt: String?
}

struct DeviceProfile: Codable {
    var schema: Int?
    var udid: String
    var cards: [StoredCard]
    var passcode: PasscodeRecord?
}

struct OriginalManifest: Codable {
    var capturedAt: String?
    var suspectModified: Bool?
}

struct ArtworkHistoryEntry: Codable {
    let file: String
    var sha256: String?
    var appliedAt: String?
}

struct ArtworkHistoryItem: Identifiable {
    let id: String
    let url: URL
    let appliedAt: String?
}

enum DeviceProfileStore {
    static var supportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FaceLift", isDirectory: true)
    }

    static func isValidUDID(_ udid: String) -> Bool {
        udid.range(of: "^[A-Za-z0-9-]{16,80}$", options: .regularExpression) != nil
    }

    static func isValidCard(_ cardId: String) -> Bool {
        cardId.range(of: "^[-A-Za-z0-9_+=]{16,64}$", options: .regularExpression) != nil
    }

    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    // MARK: Paths

    static func deviceDirectory(_ udid: String) -> URL? {
        guard isValidUDID(udid) else { return nil }
        return supportRoot.appendingPathComponent("Devices/\(udid)", isDirectory: true)
    }

    static func skinURL(udid: String, cardId: String) -> URL? {
        guard isValidCard(cardId), let base = deviceDirectory(udid) else { return nil }
        return base.appendingPathComponent("skins/\(cardId).png")
    }

    static func originalDirectory(udid: String, cardId: String) -> URL? {
        guard isValidCard(cardId), let base = deviceDirectory(udid) else { return nil }
        return base.appendingPathComponent("originals/\(cardId)", isDirectory: true)
    }

    static func historyDirectory(udid: String, cardId: String) -> URL? {
        guard isValidCard(cardId), let base = deviceDirectory(udid) else { return nil }
        return base.appendingPathComponent("history/\(cardId)", isDirectory: true)
    }

    static var indexURL: URL { supportRoot.appendingPathComponent("devices.json") }
    static var legacyDirectory: URL { supportRoot.appendingPathComponent("Legacy", isDirectory: true) }

    // MARK: JSON

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Index

    static func loadIndex() -> DeviceIndex {
        read(DeviceIndex.self, from: indexURL) ?? DeviceIndex(schema: 1, devices: [])
    }

    static func saveIndex(_ index: DeviceIndex) {
        var index = index
        index.schema = 1
        write(index, to: indexURL)
    }

    /// Records a connection and returns the updated index.
    static func recordSeen(_ device: DeviceInfo) -> DeviceIndex {
        var index = loadIndex()
        guard let udid = device.udid, isValidUDID(udid) else { return index }
        var devices = index.devices ?? []
        let stamp = now()
        if let i = devices.firstIndex(where: { $0.udid == udid }) {
            devices[i].name = device.name ?? devices[i].name
            devices[i].product = device.product ?? devices[i].product
            devices[i].lastVersion = device.version ?? devices[i].lastVersion
            devices[i].lastSeen = stamp
        } else {
            devices.append(DeviceRecord(
                udid: udid, name: device.name, customName: nil, product: device.product,
                lastVersion: device.version, firstSeen: stamp, lastSeen: stamp
            ))
        }
        index.devices = devices
        saveIndex(index)
        return index
    }

    // MARK: Profiles

    static func loadProfile(udid: String) -> DeviceProfile {
        if let base = deviceDirectory(udid),
           let profile = read(DeviceProfile.self, from: base.appendingPathComponent("profile.json")) {
            return profile
        }
        return DeviceProfile(schema: 1, udid: udid, cards: [], passcode: nil)
    }

    private static func saveProfile(_ profile: DeviceProfile) {
        guard let base = deviceDirectory(profile.udid) else { return }
        var profile = profile
        profile.schema = 1
        write(profile, to: base.appendingPathComponent("profile.json"))
    }

    /// Replaces the card list, keeping metadata of cards that stay.
    static func saveCards(udid: String, ids: [String], source: String) {
        var profile = loadProfile(udid: udid)
        let known = Dictionary(profile.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        profile.cards = ids.compactMap { id in
            guard isValidCard(id), seen.insert(id).inserted else { return nil }
            return known[id] ?? StoredCard(id: id, addedAt: now(), source: source)
        }
        saveProfile(profile)
    }

    static func recordPasscode(udid: String, theme: String, version: String) {
        var profile = loadProfile(udid: udid)
        profile.passcode = PasscodeRecord(lastAppliedTheme: theme, lastAppliedVersion: version, lastAppliedAt: now())
        saveProfile(profile)
    }

    // MARK: Originals and history

    static func originalManifest(udid: String, cardId: String) -> OriginalManifest? {
        guard let dir = originalDirectory(udid: udid, cardId: cardId) else { return nil }
        return read(OriginalManifest.self, from: dir.appendingPathComponent("manifest.json"))
    }

    static func hasOriginal(udid: String, cardId: String) -> Bool {
        originalManifest(udid: udid, cardId: cardId) != nil
    }

    static func originalPreviewURL(udid: String, cardId: String) -> URL? {
        guard let dir = originalDirectory(udid: udid, cardId: cardId) else { return nil }
        let url = dir.appendingPathComponent("preview.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Artwork FaceLift has written to this card, newest first.
    static func history(udid: String, cardId: String) -> [ArtworkHistoryItem] {
        guard let dir = historyDirectory(udid: udid, cardId: cardId),
              let entries = read([ArtworkHistoryEntry].self, from: dir.appendingPathComponent("history.json"))
        else { return [] }
        return entries.compactMap { entry in
            let url = dir.appendingPathComponent((entry.file as NSString).lastPathComponent)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ArtworkHistoryItem(id: entry.file, url: url, appliedAt: entry.appliedAt)
        }
    }

    // MARK: Legacy store

    /// Moves the pre-profile cards.json and skins/ into Legacy/ once.
    /// Their owner is unknown, so they are never assigned to a device here.
    @discardableResult
    static func migrateLegacyStore() -> Bool {
        let fm = FileManager.default
        var moved = false
        // Skins saved under the AirCard branding predate FaceLift/skins.
        let airCardSkins = supportRoot.deletingLastPathComponent().appendingPathComponent("AirCard/skins", isDirectory: true)
        let sources: [(URL, String)] = [
            (supportRoot.appendingPathComponent("cards.json"), "cards.json"),
            (supportRoot.appendingPathComponent("skins", isDirectory: true), "skins"),
            (airCardSkins, "skins"),
        ]
        for (source, name) in sources {
            let target = legacyDirectory.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { continue }
            try? fm.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
            if (try? fm.moveItem(at: source, to: target)) != nil { moved = true }
        }
        return moved
    }

    static func legacyCardIds() -> [String] {
        let hashes = read([String].self, from: legacyDirectory.appendingPathComponent("cards.json")) ?? []
        var seen = Set<String>()
        return hashes.filter { isValidCard($0) && seen.insert($0).inserted }
    }

    static func addLegacyCardIds(_ ids: [String]) {
        var seen = Set<String>()
        let merged = (legacyCardIds() + ids).filter { seen.insert($0).inserted }
        write(merged, to: legacyDirectory.appendingPathComponent("cards.json"))
    }

    static func legacySkinURL(cardId: String) -> URL? {
        let url = legacyDirectory.appendingPathComponent("skins/\(cardId).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// A queued artwork read, bound to the iPhone it was queued for.
struct SkinPullRequest: Equatable {
    let udid: String
    let cardId: String
}

/// Cards saved by an earlier version, offered to the iPhone just connected.
struct LegacyClaim: Identifiable {
    let udid: String
    let deviceName: String
    let count: Int
    var id: String { udid }
}

struct ArtworkHistoryTarget: Identifiable {
    let udid: String
    let cardId: String
    var id: String { udid + "/" + cardId }
}
