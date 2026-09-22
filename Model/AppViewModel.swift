import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - View Model

@MainActor
class AppViewModel: ObservableObject {
    @Published var selectedTab: AppTab = .walletCards
    @Published var loadedPasscodeTheme: PasscodeThemeInfo? = nil
    @Published var isInspectingTheme = false
    @Published var targetTelephonyVersion: String = "TelephonyUI-10"
    @Published var passcodeLanguageTarget: PasscodeLanguageTarget = .macOSPreferred
    @Published var passcodeBoldTarget: PasscodeBoldTarget = .both
    
    // Theme Creator Properties
    @Published var passcodeTabMode: PasscodeTabMode = .applyTheme
    @Published var creatorSubMode: CreatorSubMode = .posterSlice
    @Published var creatorPosterImage: NSImage? = nil
    @Published var creatorUsesDefaultPoster = false
    @Published var creatorPosterZoom: Double = 1.0
    @Published var creatorPosterOffset: CGPoint = .zero
    @Published var creatorMaskToCircles: Bool = false
    @Published var creatorCustomKeys: [String: NSImage] = [:]
    @Published var creatorSlicedKeys: [String: NSImage] = [:]
    @Published var creatorRawIndividualImages: [String: NSImage] = [:]
    @Published var creatorIndividualOffsets: [String: CGPoint] = [:]
    @Published var creatorIndividualZooms: [String: Double] = [:]
    @Published var selectedKeyDigit: String? = nil
    
    @Published var device: DeviceInfo?
    @Published var isCheckingDevice = false
    @Published var isScanningCards = false
    @Published var cards: [CardItem] = []
    
    @Published var isFlashing = false
    @Published var progress: Double = 0.0
    @Published var logs: [ActivityLogLine] = []
    @Published var showSuccessAlert = false
    @Published var didClearPasscodeCache = false
    @Published var errorMessage: String?
    private var statusTemplate = "Ready"
    private var statusArguments: [String] = []
    
    @Published var showAddCardSheet = false
    @Published var manualHashInput = ""
    @Published var showLogs = false
    @Published var isPullingSkins = false
    private var skinPullQueue: [SkinPullRequest] = []

    /// UDID of the iPhone whose cards are shown. Survives disconnects; it
    /// follows the connected iPhone on the next device check.
    @Published private(set) var activeProfileUDID: String?
    @Published var knownDevices: [DeviceRecord] = []
    @Published var legacyClaim: LegacyClaim?
    @Published private(set) var legacyCardCount = 0
    @Published var historyTarget: ArtworkHistoryTarget?
    
    private var scanProcess: Process?
    private let scriptDir: String
    // Cards are stored per iPhone (DeviceProfileStore). The keys and dotfiles
    // below are only read once, into Legacy/, to migrate older installs.
    private static let legacyStorageKeys = [
        "jetems.facelift.savedCards",
        "mak5er.aircard.savedCards",
        "mak5er.savedCards",
        "LumiCards.savedCards",
    ]
    private static let legacyCardFiles = [
        "~/.facelift_cards.json",
        "~/.aircard_cards.json",
        "~/.lumicards_cards.json",
    ]
    
    nonisolated static let cardRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,44})(?:\\.pkpass|\\.cache|\\.pkcache|/|\\s|\"|'|\\)|,|$)"),
        try! NSRegularExpression(pattern: "/([-A-Za-z0-9_+=]{20,44})\\.(?:pkpass|cache|pkcache)"),
        try! NSRegularExpression(pattern: "(?<![A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{27}=)(?![A-Za-z0-9+/_-])")
    ]
    
    init() {
        let cwd = FileManager.default.currentDirectoryPath
        if let resPath = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: resPath + "/facelift_backend.py") {
            self.scriptDir = resPath
        } else if FileManager.default.fileExists(atPath: cwd + "/facelift_backend.py") {
            self.scriptDir = cwd
        } else {
            self.scriptDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        }
        
        prepareStore()
        if let last = DeviceProfileStore.loadIndex().lastActiveUDID, DeviceProfileStore.isValidUDID(last) {
            activateProfile(last)
            log("Loaded %@ card(s) of %@.", "\(cards.count)", activeProfileName)
        }
        loadDefaultPoster(announce: false)
        checkDevice()
    }
    
    var localizedStatus: String {
        if statusArguments.isEmpty {
            return localizeBackend(statusTemplate)
        }
        return L(statusTemplate, args: statusArguments)
    }

    func setStatus(_ template: String, _ args: String...) {
        objectWillChange.send()
        statusTemplate = template
        statusArguments = args
    }

    func dismissScanPrompt() {
        if statusTemplate == "Double-click Side button, pass Face ID, then tap your card..." {
            setStatus("Ready")
        }
    }

    func log(_ template: String, _ args: String...) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        logs.append(ActivityLogLine(time: timestamp, template: template, args: args, backend: false))
    }

    func logBackend(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        logs.append(ActivityLogLine(time: timestamp, template: message, args: [], backend: true))
    }
    
    nonisolated private static var pythonExecutableURL: URL {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }
    
    nonisolated private static var deviceHelperExecutableURL: URL? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("bin/device_helper").path)
        }
        candidates.append("/Applications/FaceLift.app/Contents/Resources/bin/device_helper")
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
    
    nonisolated private static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        var extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        if let res = Bundle.main.resourceURL {
            extraPaths.insert(res.appendingPathComponent("bin").path, at: 0)
        }
        extraPaths.insert("/Applications/FaceLift.app/Contents/Resources/bin", at: 0)
        env["PATH"] = (extraPaths + [path]).joined(separator: ":")
        
        var libPaths = ["/Applications/FaceLift.app/Contents/Resources/lib"]
        if let res = Bundle.main.resourceURL {
            libPaths.insert(res.appendingPathComponent("lib").path, at: 0)
        }
        let curDyld = env["DYLD_LIBRARY_PATH"] ?? ""
        env["DYLD_LIBRARY_PATH"] = (libPaths + (curDyld.isEmpty ? [] : [curDyld])).joined(separator: ":")
        return env
    }
    
    nonisolated static func prepareCardImage(srcURL: URL, dstURL: URL) -> Bool {
        guard let image = NSImage(contentsOf: srcURL) else { return false }
        let targetSize = CGSize(width: 1536, height: 969)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return false }
        
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        
        let imgSize = image.size
        let scale = max(targetSize.width / imgSize.width, targetSize.height / imgSize.height)
        let scaledWidth = imgSize.width * scale
        let scaledHeight = imgSize.height * scale
        let x = (targetSize.width - scaledWidth) / 2.0
        let y = (targetSize.height - scaledHeight) / 2.0
        
        image.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight),
                   from: CGRect(origin: .zero, size: imgSize),
                   operation: .copy,
                   fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try pngData.write(to: dstURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Persistence (per iPhone)

    /// Moves every pre-profile card list into Legacy/. Nothing is assigned
    /// to an iPhone until the user says which one it belongs to.
    private func prepareStore() {
        if DeviceProfileStore.migrateLegacyStore() {
            log("Moved cards saved by an earlier version aside until you choose their iPhone.")
        }
        let found = Self.migrateLegacyCards()
        if !found.isEmpty {
            DeviceProfileStore.addLegacyCardIds(found)
        }
        legacyCardCount = DeviceProfileStore.legacyCardIds().count
    }

    var activeProfileName: String {
        guard let udid = activeProfileUDID else { return "iPhone" }
        return knownDevices.first(where: { $0.udid == udid })?.displayName ?? "iPhone"
    }

    /// True when the connected iPhone is the one whose cards are shown.
    var isActiveDeviceConnected: Bool {
        guard let udid = device?.udid, device?.connected == true else { return false }
        return udid == activeProfileUDID
    }

    /// Shown above the card list when writes are blocked because the list
    /// belongs to an iPhone that is not connected.
    var profileNotice: String? {
        guard activeProfileUDID != nil, !isActiveDeviceConnected else { return nil }
        return L("Showing cards of %@. Connect this iPhone to write to it.", activeProfileName)
    }

    private func activateProfile(_ udid: String) {
        activeProfileUDID = udid
        cards = Self.loadCards(for: udid)
        var index = DeviceProfileStore.loadIndex()
        index.lastActiveUDID = udid
        DeviceProfileStore.saveIndex(index)
        knownDevices = index.devices ?? []
    }

    private static func loadCards(for udid: String) -> [CardItem] {
        DeviceProfileStore.loadProfile(udid: udid).cards.map { stored in
            var card = CardItem(id: stored.id)
            if let url = DeviceProfileStore.skinURL(udid: udid, cardId: stored.id),
               FileManager.default.fileExists(atPath: url.path),
               let image = NSImage(contentsOf: url) {
                card.customImageURL = url
                card.customImage = image
            }
            return card
        }
    }

    /// Follows the connected iPhone: its own cards replace the list shown.
    private func reconcileActiveProfile(with dev: DeviceInfo) {
        guard dev.connected, let udid = dev.udid, DeviceProfileStore.isValidUDID(udid) else { return }
        knownDevices = DeviceProfileStore.recordSeen(dev).devices ?? []
        guard udid != activeProfileUDID else { return }
        // A running write stays bound to its iPhone; switch on a later check.
        guard !isFlashing && !isPullingSkins else { return }
        if isScanningCards { stopCardScanning() }
        skinPullQueue.removeAll()
        activateProfile(udid)
        let name = dev.name ?? "iPhone"
        setStatus("Showing cards of %@.", name)
        log("Switched to the cards of %@ (%@ card(s)).", name, "\(cards.count)")
        offerLegacyCardsIfNeeded(udid: udid, deviceName: name)
    }

    private func offerLegacyCardsIfNeeded(udid: String, deviceName: String) {
        guard cards.isEmpty, legacyCardCount > 0,
              DeviceProfileStore.loadIndex().legacyPromptDismissed != true else { return }
        legacyClaim = LegacyClaim(udid: udid, deviceName: deviceName, count: legacyCardCount)
    }

    /// Adds the cards saved by an earlier version to the shown iPhone.
    func importLegacyCards() {
        guard let udid = activeProfileUDID else { return }
        var added = 0
        for id in DeviceProfileStore.legacyCardIds() where !cards.contains(where: { $0.id == id }) {
            var card = CardItem(id: id)
            if let source = DeviceProfileStore.legacySkinURL(cardId: id),
               let dest = DeviceProfileStore.skinURL(udid: udid, cardId: id) {
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: source, to: dest)
                }
                card.customImageURL = dest
                card.customImage = NSImage(contentsOf: dest)
            }
            cards.append(card)
            added += 1
        }
        saveCards(source: "legacy")
        log("Added %@ card(s) from an earlier version to %@.", "\(added)", activeProfileName)
    }

    func stopOfferingLegacyCards() {
        var index = DeviceProfileStore.loadIndex()
        index.legacyPromptDismissed = true
        DeviceProfileStore.saveIndex(index)
    }

    func storeSkin(for cardId: String, url: URL) {
        guard let udid = activeProfileUDID,
              let idx = cards.firstIndex(where: { $0.id == cardId }),
              let dest = DeviceProfileStore.skinURL(udid: udid, cardId: cardId) else { return }
        if url.path != dest.path {
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        let stored = FileManager.default.fileExists(atPath: dest.path) ? dest : url
        cards[idx].customImageURL = stored
        cards[idx].customImage = NSImage(contentsOf: stored)
        cards[idx].isSelected = true
    }

    func queueSkinPulls(ids: [String], replacingStored: Bool) {
        guard isActiveDeviceConnected, let udid = device?.udid, !isFlashing else { return }
        if device?.isWiFi == true {
            setStatus("Reading artwork over Wi-Fi may fail — connect via USB.")
            log("Warning: reading artwork over Wi-Fi is unreliable; use a USB connection.")
        }
        for id in ids {
            // The first read also saves the untouched original.
            let needsOriginal = !DeviceProfileStore.hasOriginal(udid: udid, cardId: id)
            let hasShown = DeviceProfileStore.skinURL(udid: udid, cardId: id)
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if !replacingStored && hasShown && !needsOriginal { continue }
            let request = SkinPullRequest(udid: udid, cardId: id)
            if !skinPullQueue.contains(request) {
                skinPullQueue.append(request)
            }
        }
        pumpSkinPulls()
    }

    func pumpSkinPulls() {
        guard !isPullingSkins, !isFlashing, let current = device?.udid else { return }
        // Requests queued for another iPhone are dropped, never redirected.
        skinPullQueue.removeAll { $0.udid != current }
        guard !skinPullQueue.isEmpty else { return }
        let request = skinPullQueue.removeFirst()
        guard let dest = DeviceProfileStore.skinURL(udid: request.udid, cardId: request.cardId) else {
            pumpSkinPulls()
            return
        }
        let capture = !DeviceProfileStore.hasOriginal(udid: request.udid, cardId: request.cardId)
        isPullingSkins = true
        setStatus(capture ? "Saving original artwork from iPhone..." : "Reading artwork from iPhone...")
        let scriptDir = self.scriptDir
        let arguments = [capture ? "--snapshot-card" : "--pull-card", request.udid, request.cardId, dest.path]
        Task.detached {
            let json = AppViewModel.runBackendJSON(scriptDir: scriptDir, arguments: arguments)
            let ok = (json?["ok"] as? Bool) == true
            let asset = json?["asset"] as? String ?? ""
            let reason = json?["reason"] as? String ?? "sync"
            let suspect = (json?["suspectModified"] as? Bool) == true
            await MainActor.run {
                self.isPullingSkins = false
                let short = String(request.cardId.prefix(8))
                if capture && DeviceProfileStore.hasOriginal(udid: request.udid, cardId: request.cardId) {
                    self.log("Saved the original artwork of card %@.", short)
                    if suspect {
                        self.log("Card %@ may already have been changed by an earlier FaceLift; its saved original may not be the issuer's design.", short)
                    }
                }
                if ok, let image = NSImage(contentsOf: dest) {
                    if request.udid == self.activeProfileUDID,
                       let idx = self.cards.firstIndex(where: { $0.id == request.cardId }) {
                        self.cards[idx].customImageURL = dest
                        self.cards[idx].customImage = image
                    }
                    self.setStatus("Read artwork for %@.", short)
                    self.log("Read %@ artwork for card %@.", asset, short)
                } else if reason == "card_not_in_profile" || reason == "destination" {
                    self.log("Card %@ does not belong to the connected iPhone; skipped.", short)
                } else if reason == "sync" {
                    self.skinPullQueue.removeAll()
                    self.setStatus("Could not read artwork from iPhone.")
                    self.log("Could not read artwork from iPhone.")
                } else {
                    self.log("No artwork found on iPhone for %@.", short)
                    if self.skinPullQueue.isEmpty {
                        self.setStatus("No artwork found on iPhone for %@.", short)
                    }
                }
                self.pumpSkinPulls()
            }
        }
    }

    /// Runs one backend command and returns its last JSON line.
    nonisolated static func runBackendJSON(scriptDir: String, arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = AppViewModel.pythonExecutableURL
        process.environment = AppViewModel.processEnvironment
        process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
        process.arguments = ["facelift_backend.py"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    func saveCards(source: String = "manual") {
        guard let udid = activeProfileUDID else { return }
        DeviceProfileStore.saveCards(udid: udid, ids: cards.map(\.id), source: source)
    }

    /// Collects hashes from pre-cards.json storage, then retires those sources
    /// (UserDefaults keys removed, dotfiles renamed to *.migrated) so they are
    /// never read again.
    private static func migrateLegacyCards() -> [String] {
        var loaded: [String] = []
        let defaults = UserDefaults.standard
        if let saved = legacyStorageKeys.lazy.compactMap({ defaults.stringArray(forKey: $0) }).first(where: { !$0.isEmpty }) {
            loaded.append(contentsOf: saved)
        }
        let fm = FileManager.default
        for p in legacyCardFiles {
            let path = NSString(string: p).expandingTildeInPath
            guard let data = fm.contents(atPath: path) else { continue }
            if let hashes = try? JSONDecoder().decode([String].self, from: data) {
                for h in hashes where !loaded.contains(h) {
                    loaded.append(h)
                }
            }
            try? fm.moveItem(atPath: path, toPath: path + ".migrated")
        }
        for key in legacyStorageKeys {
            defaults.removeObject(forKey: key)
        }
        return loaded
    }
    
    func addCardHash(_ raw: String) -> (added: Int, rejected: [String]) {
        guard activeProfileUDID != nil else {
            errorMessage = L("Connect an iPhone first. Cards are saved for the iPhone they belong to.")
            return (0, [raw])
        }
        let components = raw.components(separatedBy: CharacterSet(charactersIn: " \n\r\t,;"))
        var addedCount = 0
        var rejected: [String] = []
        for comp in components {
            let clean = comp.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let validHash = clean.range(of: "^[-A-Za-z0-9_+=]{16,64}$", options: .regularExpression) != nil
            if validHash && !cards.contains(where: { $0.id == clean }) {
                cards.append(CardItem(id: clean))
                addedCount += 1
                log("Added card: %@", clean)
            } else if !comp.isEmpty {
                rejected.append(clean.isEmpty ? comp : clean)
            }
        }
        if addedCount > 0 {
            saveCards()
            setStatus("Added %@ card hash(es) to the list.", "\(addedCount)")
        }
        return (addedCount, rejected)
    }
    
    func deleteCard(id: String) {
        cards.removeAll { $0.id == id }
        saveCards()
        log("Removed card: %@", id)
    }
    
    func clearAllCards() {
        cards.removeAll()
        saveCards()
        log("Cleared all cards.")
    }
    
    func setCardImage(for cardId: String, url: URL) {
        storeSkin(for: cardId, url: url)
        log("Assigned custom skin to card: %@...", String(cardId.prefix(12)))
    }
    
    func clearCardImage(for cardId: String) {
        if let idx = cards.firstIndex(where: { $0.id == cardId }) {
            cards[idx].customImageURL = nil
            cards[idx].customImage = nil
            if let udid = activeProfileUDID, let url = DeviceProfileStore.skinURL(udid: udid, cardId: cardId) {
                try? FileManager.default.removeItem(at: url)
            }
            log("Cleared custom skin for: %@...", String(cardId.prefix(12)))
        }
    }
    
    // MARK: - Original Artwork and History

    func hasOriginalArtwork(for cardId: String) -> Bool {
        guard let udid = activeProfileUDID else { return false }
        return DeviceProfileStore.hasOriginal(udid: udid, cardId: cardId)
    }

    var canRestoreOriginal: Bool { isActiveDeviceConnected && !isBusy && !isScanningCards }

    func showArtworkHistory(for cardId: String) {
        guard let udid = activeProfileUDID else { return }
        historyTarget = ArtworkHistoryTarget(udid: udid, cardId: cardId)
    }

    /// Puts an earlier design back on the card; Flash writes it.
    func useHistoryArtwork(_ url: URL, for cardId: String) {
        storeSkin(for: cardId, url: url)
        log("Chose an earlier design for card %@. Flash to write it.", String(cardId.prefix(12)))
    }

    /// Writes the artwork saved before FaceLift first changed the card back
    /// to the iPhone, byte for byte.
    func restoreOriginalArtwork(for cardId: String) {
        guard let udid = device?.udid, isActiveDeviceConnected else {
            errorMessage = L("Connect %@ to restore its original artwork.", activeProfileName)
            return
        }
        guard !isFlashing && !isPullingSkins else { return }
        guard DeviceProfileStore.hasOriginal(udid: udid, cardId: cardId) else {
            errorMessage = L("No original artwork has been saved for this card yet.")
            return
        }
        isFlashing = true
        didClearPasscodeCache = false
        errorMessage = nil
        showLogs = true
        progress = 0
        let short = String(cardId.prefix(12))
        setStatus("Restoring original artwork of %@...", short)
        log("Restoring original artwork of %@...", short)
        let scriptDir = self.scriptDir
        Task.detached {
            let json = AppViewModel.runBackendJSON(scriptDir: scriptDir, arguments: ["--restore-original", udid, cardId])
            let ok = (json?["ok"] as? Bool) == true
            let detail = (json?["error"] as? String) ?? (json?["reason"] as? String) ?? ""
            await MainActor.run {
                self.isFlashing = false
                guard ok else {
                    self.errorMessage = L("Could not restore the original artwork. Check the log.")
                    self.setStatus("Could not restore the original artwork. Check the log.")
                    self.log("Restoring the original artwork failed: %@", detail)
                    return
                }
                self.progress = 1
                self.showOriginalArtwork(udid: udid, cardId: cardId)
                self.setStatus("Original artwork restored. Force-close Wallet to see it.")
                self.log("Restored the original artwork of card %@.", short)
            }
        }
    }

    private func showOriginalArtwork(udid: String, cardId: String) {
        guard let dest = DeviceProfileStore.skinURL(udid: udid, cardId: cardId) else { return }
        try? FileManager.default.removeItem(at: dest)
        if let preview = DeviceProfileStore.originalPreviewURL(udid: udid, cardId: cardId) {
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: preview, to: dest)
        }
        guard udid == activeProfileUDID, let idx = cards.firstIndex(where: { $0.id == cardId }) else { return }
        let exists = FileManager.default.fileExists(atPath: dest.path)
        cards[idx].customImageURL = exists ? dest : nil
        cards[idx].customImage = exists ? NSImage(contentsOf: dest) : nil
        // Already on the iPhone; keep it out of the next flash.
        cards[idx].isSelected = false
    }

    // MARK: - Device Connection
    
    func checkDevice(silent: Bool = false) {
        guard !isCheckingDevice else { return }
        isCheckingDevice = true
        if !silent { setStatus("Checking connected devices...") }
        let scriptDir = self.scriptDir
        // Keeps the shown iPhone selected while it stays connected.
        let arguments = ["facelift_backend.py", "--device"]
            + (activeProfileUDID.map { ["--prefer", $0] } ?? [])
        
        Task.detached {
            let process = Process()
            process.executableURL = AppViewModel.pythonExecutableURL
            process.environment = AppViewModel.processEnvironment
            process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            process.arguments = arguments
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let dev = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
                    await MainActor.run {
                        let changed = self.device?.connected != dev.connected
                            || self.device?.udid != dev.udid
                            || self.device?.product != dev.product
                            || self.device?.connection != dev.connection
                        self.device = dev
                        self.isCheckingDevice = false
                        if dev.connected {
                            if let cacheVersion = dev.passcodeCacheVersion {
                                self.targetTelephonyVersion = cacheVersion
                            }
                            let deviceName = dev.name ?? "iPhone"
                            if changed || !silent {
                                if dev.isWiFi {
                                    self.setStatus("Connected to %@ via Wi-Fi", deviceName)
                                } else {
                                    self.setStatus("Connected to %@", deviceName)
                                }
                                self.log("Device connected (%@): %@ (%@, iOS %@)", dev.isWiFi ? "Wi-Fi" : "USB", deviceName, dev.product ?? "", dev.version ?? "")
                            }
                            self.reconcileActiveProfile(with: dev)
                        } else if dev.error == "device_helper_missing" {
                            if changed || !silent {
                                self.setStatus("Device tools are missing from this build.")
                                self.log("Bundled device_helper not found — detection cannot run.")
                            }
                        } else if changed || !silent {
                            self.setStatus("No iPhone found. Please connect via USB.")
                        }
                    }
                } else {
                    await MainActor.run {
                        self.isCheckingDevice = false
                        if !silent { self.setStatus("No iPhone found. Please connect via USB.") }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCheckingDevice = false
                    if !silent { self.setStatus("Device detection failed: %@", error.localizedDescription) }
                }
            }
        }
    }
    
    // MARK: - Live Card Scanner
    
    func toggleCardScanning() {
        if isScanningCards {
            stopCardScanning()
        } else {
            startCardScanning()
        }
    }
    
    func startCardScanning() {
        guard !isScanningCards else { return }
        guard let deviceHelper = AppViewModel.deviceHelperExecutableURL else {
            errorMessage = L("Device tools are missing from this build.")
            log("Bundled device_helper not found — cannot scan.")
            return
        }
        guard let udid = device?.udid, device?.connected == true else {
            errorMessage = L("No iPhone connected.")
            return
        }
        guard udid == activeProfileUDID else {
            errorMessage = L("The card list is switching to the connected iPhone. Try again in a moment.")
            return
        }
        isScanningCards = true
        setStatus("Double-click Side button, pass Face ID, then tap your card...")
        log("Started scanning device logs for cards...")
        
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = deviceHelper
        proc.environment = AppViewModel.processEnvironment
        proc.arguments = ["syslog", udid]
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        self.scanProcess = proc
        // Launch before yielding so Stop cannot race with a pending launch.
        do {
            try proc.run()
        } catch {
            scanProcess = nil
            isScanningCards = false
            setStatus("Could not start card scanning.")
            log("Syslog monitor failed to start: %@", error.localizedDescription)
            return
        }
        
        let dummyHashes = [
            "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
            "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
            "hwAtAmHKYwsQrJbT5cTNDsaxVME="
        ]
        
        Task.detached {
            do {
                let handle = pipe.fileHandleForReading
                var buffer = Data()
                
                // Drain the pipe through EOF, including the last buffered record
                // when the helper exits. isRunning can become false too early.
                while true {
                    let chunk = try handle.read(upToCount: 65536) ?? Data()
                    if chunk.isEmpty {
                        if buffer.isEmpty { break }
                        buffer.append(0x0A)
                    } else {
                        buffer.append(chunk)
                    }
                    
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                        
                        guard let line = String(data: lineData, encoding: .utf8) else { continue }
                        if line.hasPrefix("FaceLift scanner: ") {
                            await MainActor.run {
                                guard self.scanProcess === proc else { return }
                                self.logBackend(line)
                            }
                            continue
                        }
                        let lower = line.lowercased()
                        
                        let isWalletSubsystem = lower.contains("passd") ||
                                                lower.contains("passbook") ||
                                                lower.contains("passkit") ||
                                                lower.contains("stockholm") ||
                                                lower.contains("nanopassd") ||
                                                lower.contains("wallet") ||
                                                lower.contains("/cards/")
                        
                        guard isWalletSubsystem else { continue }
                        
                        let isWalletContext = lower.contains("card") ||
                                              lower.contains("pass") ||
                                              lower.contains("payment") ||
                                              lower.contains("pkpass") ||
                                              lower.contains("uniqueid") ||
                                              lower.contains("identifier") ||
                                              lower.contains("face") ||
                                              lower.contains("cache") ||
                                              lower.contains("stockholm") ||
                                              lower.contains("/cards/")
                        
                        guard isWalletContext else { continue }
                        
                        for regex in AppViewModel.cardRegexes {
                            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                            for m in matches {
                                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: line) {
                                    let candidate = String(line[r])
                                    if candidate.count == 36 && candidate.contains("-") { continue }
                                    if dummyHashes.contains(candidate) { continue }
                                    
                                    await MainActor.run {
                                        guard self.scanProcess === proc else { return }
                                        self.addScannedCard(candidate, udid: udid)
                                    }
                                }
                            }
                        }
                    }
                    if chunk.isEmpty { break }
                }
                proc.waitUntilExit()
                await MainActor.run {
                    guard self.scanProcess === proc else { return }
                    self.scanProcess = nil
                    self.isScanningCards = false
                    self.setStatus("Card scanning ended. Check the log and reconnect the iPhone to retry.")
                    self.log("Syslog monitor exited (status %@). Total cards: %@.", "\(proc.terminationStatus)", "\(self.cards.count)")
                    self.saveCards()
                }
            } catch {
                if proc.isRunning { proc.terminate() }
                proc.waitUntilExit()
                await MainActor.run {
                    guard self.scanProcess === proc else { return }
                    self.scanProcess = nil
                    self.log("Syslog monitor stopped: %@", error.localizedDescription)
                    self.isScanningCards = false
                    self.setStatus("Card scanning failed. Check the log and retry.")
                }
            }
        }
    }
    
    /// Saves a scanned card to the iPhone the scan was started on, even if
    /// another iPhone's cards are shown by the time the log line arrives.
    private func addScannedCard(_ cardId: String, udid: String) {
        guard udid == activeProfileUDID else {
            let ids = DeviceProfileStore.loadProfile(udid: udid).cards.map(\.id)
            if !ids.contains(cardId) {
                DeviceProfileStore.saveCards(udid: udid, ids: ids + [cardId], source: "scan")
            }
            return
        }
        guard !cards.contains(where: { $0.id == cardId }) else { return }
        cards.append(CardItem(id: cardId))
        saveCards(source: "scan")
        log("Found card: %@", cardId)
        queueSkinPulls(ids: [cardId], replacingStored: false)
        NSSound(named: "Glass")?.play()
    }

    func stopCardScanning() {
        let process = scanProcess
        scanProcess = nil
        if let process, process.isRunning { process.terminate() }
        isScanningCards = false
        dismissScanPrompt()
        saveCards()
        log("Scanning stopped. Total cards: %@.", "\(cards.count)")
    }
    
    // MARK: - Skin Application
    
    func applySkin() {
        guard let udid = device?.udid, device?.connected == true else {
            errorMessage = L("No iPhone connected.")
            return
        }
        // Only the connected iPhone's own cards may be written to it.
        guard udid == activeProfileUDID else {
            errorMessage = L("These cards belong to %@, not to the connected iPhone.", activeProfileName)
            return
        }
        let selectedCardsWithSkin = cards.filter { $0.isSelected && $0.customImageURL != nil }
        guard !selectedCardsWithSkin.isEmpty else {
            errorMessage = L("Please assign a skin image to at least one selected card.")
            return
        }
        
        isFlashing = true
        didClearPasscodeCache = false
        showLogs = true
        progress = 0.0
        log("Starting skin application for %@ card(s)...", "\(selectedCardsWithSkin.count)")
        let scriptDir = self.scriptDir
        
        Task.detached {
            var flashFailed = false
            let totalCards = Double(selectedCardsWithSkin.count)
            for (idx, card) in selectedCardsWithSkin.enumerated() {
                guard let imgURL = card.customImageURL else { continue }
                
                // Save the untouched original before the first change, so
                // the card can always go back to it.
                if !DeviceProfileStore.hasOriginal(udid: udid, cardId: card.id) {
                    await MainActor.run {
                        self.setStatus("[%@/%@] Saving original artwork of %@...", "\(idx + 1)", "\(selectedCardsWithSkin.count)", String(card.id.prefix(10)))
                    }
                    _ = AppViewModel.runBackendJSON(scriptDir: scriptDir, arguments: ["--snapshot-card", udid, card.id])
                    if !DeviceProfileStore.hasOriginal(udid: udid, cardId: card.id) {
                        flashFailed = true
                        await MainActor.run {
                            self.log("Could not save the original artwork of %@, so the card was not changed.", String(card.id.prefix(12)))
                        }
                        break
                    }
                }

                let preparedPath = "/tmp/facelift_prep_\(idx).png"
                
                await MainActor.run {
                    self.setStatus("[%@/%@] Preparing skin for %@...", "\(idx + 1)", "\(selectedCardsWithSkin.count)", String(card.id.prefix(10)))
                    self.progress = (Double(idx) + 0.05) / totalCards
                    self.log("Flashing card [%@/%@]: %@", "\(idx + 1)", "\(selectedCardsWithSkin.count)", card.id)
                }
                
                // 1. Prepare image natively in Swift (0 external dependencies!)
                let preparedURL = URL(fileURLWithPath: preparedPath)
                let prepped = AppViewModel.prepareCardImage(srcURL: imgURL, dstURL: preparedURL)
                if !prepped {
                    let prepProcess = Process()
                    prepProcess.executableURL = AppViewModel.pythonExecutableURL
                    prepProcess.environment = AppViewModel.processEnvironment
                    prepProcess.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
                    prepProcess.arguments = ["facelift_backend.py", "--prepare-image", imgURL.path, preparedPath]
                    try? prepProcess.run()
                    prepProcess.waitUntilExit()
                }
                
                // 2. Flash card
                let flashProcess = Process()
                flashProcess.executableURL = AppViewModel.pythonExecutableURL
                flashProcess.environment = AppViewModel.processEnvironment
                flashProcess.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
                flashProcess.arguments = ["facelift_backend.py", "--flash", udid, card.id, preparedPath]
                
                let pipe = Pipe()
                let errPipe = Pipe()
                flashProcess.standardOutput = pipe
                flashProcess.standardError = errPipe
                errPipe.fileHandleForReading.readabilityHandler = { h in
                    let data = h.availableData
                    if !data.isEmpty, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        Task { @MainActor in
                            self.log("  [err] %@", text)
                        }
                    }
                }
                
                do {
                    try flashProcess.run()
                } catch {
                    let message = error.localizedDescription
                    flashFailed = true
                    await MainActor.run {
                        self.log("Failed to launch card flasher: %@", message)
                    }
                    break
                }
                
                let handle = pipe.fileHandleForReading
                var lineBuffer = ""
                
                let handleJSONLine: (String) async -> Void = { line in
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let msg = json["message"] as? String else { return }
                    
                    let step = (json["step"] as? NSNumber)?.doubleValue
                    let total = (json["total"] as? NSNumber)?.doubleValue
                    
                    await MainActor.run {
                        if let step = step, let total = total, total > 0 {
                            let subProgress = step / total
                            let currentProgress = (Double(idx) + subProgress) / totalCards
                            self.progress = min(currentProgress, 1.0)
                        }
                        self.setStatus("[%@/%@] %@", "\(idx + 1)", "\(selectedCardsWithSkin.count)", localizeBackend(msg))
                        self.logBackend(msg)
                    }
                }
                
                let processChunk: (Data) async -> Void = { data in
                    guard let text = String(data: data, encoding: .utf8) else { return }
                    lineBuffer.append(text)
                    let parts = lineBuffer.components(separatedBy: .newlines)
                    if parts.count > 1 {
                        for line in parts.dropLast() {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                await handleJSONLine(trimmed)
                            }
                        }
                        lineBuffer = parts.last ?? ""
                    }
                }
                
                while flashProcess.isRunning {
                    let data = handle.availableData
                    if data.isEmpty { usleep(50000); continue }
                    await processChunk(data)
                }
                
                let remainingData = handle.readDataToEndOfFile()
                if !remainingData.isEmpty {
                    await processChunk(remainingData)
                }
                let finalLine = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalLine.isEmpty {
                    await handleJSONLine(finalLine)
                }
                flashProcess.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil

                if flashProcess.terminationStatus != 0 {
                    flashFailed = true
                    await MainActor.run {
                        self.log("Card update failed for %@...", String(card.id.prefix(12)))
                    }
                    break
                }
                
                await MainActor.run {
                    self.progress = Double(idx + 1) / totalCards
                }
            }
            
            let didFail = flashFailed
            await MainActor.run {
                self.isFlashing = false
                if didFail {
                    self.setStatus("Failed to apply card skins.")
                    self.errorMessage = L("One or more cards could not be updated. Check the log and try again.")
                    self.log("Skin application stopped after a card update failed.")
                } else {
                    self.setStatus("Complete! All cards updated.")
                    self.showSuccessAlert = true
                    self.log("Skins successfully applied to all selected cards!")
                }
            }
        }
    }
    
    // MARK: - Passcode Theme (.passthm) Handlers
    
    func inspectPasscodeTheme(url: URL) {
        isInspectingTheme = true
        let scriptDir = self.scriptDir
        Task.detached {
            let proc = Process()
            proc.executableURL = AppViewModel.pythonExecutableURL
            proc.environment = AppViewModel.processEnvironment
            proc.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            proc.arguments = ["facelift_backend.py", "--inspect-passthm", url.path]
            
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                let name = json["name"] as? String ?? url.deletingPathExtension().lastPathComponent
                let detectedVersion = json["detected_version"] as? String ?? "TelephonyUI-10"
                let supportedVersions = json["supported_versions"] as? [String] ?? []
                let fileCount = json["file_count"] as? Int ?? 0
                var previews: [String: NSImage] = [:]
                if let keysDict = json["keys_preview"] as? [String: String] {
                    for (digit, dataUri) in keysDict {
                        if let commaIdx = dataUri.firstIndex(of: ",") {
                            let b64 = String(dataUri[dataUri.index(after: commaIdx)...])
                            if let imgData = Data(base64Encoded: b64), let nsImg = NSImage(data: imgData) {
                                previews[digit] = nsImg
                            }
                        }
                    }
                }
                let themeInfo = PasscodeThemeInfo(
                    name: name,
                    filePath: url.path,
                    detectedVersion: detectedVersion,
                    supportedVersions: supportedVersions,
                    fileCount: fileCount,
                    keysPreview: previews
                )
                await MainActor.run {
                    self.loadedPasscodeTheme = themeInfo
                    self.targetTelephonyVersion = self.device?.passcodeCacheVersion ?? detectedVersion
                    self.isInspectingTheme = false
                    self.setStatus("Loaded passcode theme '%@' (%@ assets)", name, "\(fileCount)")
                    self.log("Loaded .passthm: %@ [%@] with %@ image assets", name, detectedVersion, "\(fileCount)")
                }
            } else {
                await MainActor.run {
                    self.isInspectingTheme = false
                    self.errorMessage = L("Failed to inspect .passthm file")
                }
            }
        }
    }
    
    func flashPasscodeTheme() {
        guard let theme = loadedPasscodeTheme else { return }
        guard let dev = device, dev.isUSBConnectedIPhone, let udid = dev.udid else {
            errorMessage = L("Connect your iPhone with USB to write a passcode theme.")
            return
        }
        guard udid == activeProfileUDID else {
            errorMessage = L("The card list is switching to the connected iPhone. Try again in a moment.")
            return
        }
        
        isFlashing = true
        didClearPasscodeCache = false
        errorMessage = nil
        showLogs = true
        progress = 0.0
        setStatus("Starting passcode theme flash...")
        log("Flashing passcode theme '%@' to device...", theme.name)
        let scriptDir = self.scriptDir
        let targetVer = dev.passcodeCacheVersion ?? self.targetTelephonyVersion
        targetTelephonyVersion = targetVer
        let targetLang = self.passcodeLanguageTarget.code
        let targetBold = self.passcodeBoldTarget.code
        
        Task.detached {
            let proc = Process()
            proc.executableURL = AppViewModel.pythonExecutableURL
            proc.environment = AppViewModel.processEnvironment
            proc.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            proc.arguments = [
                "facelift_backend.py",
                "--flash-passthm",
                udid,
                theme.filePath,
                targetVer,
                targetLang,
                targetBold
            ]
            
            let pipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = errPipe
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    Task { @MainActor in
                        self.log("  [err] %@", text)
                    }
                }
            }
            try? proc.run()
            
            let handle = pipe.fileHandleForReading
            var lineBuffer = ""
            
            let handleJSONLine: (String) async -> Void = { line in
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let msg = json["message"] as? String else { return }
                
                let step = (json["step"] as? NSNumber)?.doubleValue
                let total = (json["total"] as? NSNumber)?.doubleValue
                
                await MainActor.run {
                    if let step = step, let total = total, total > 0 {
                        self.progress = min(step / total, 1.0)
                    }
                    self.setStatus(msg)
                    self.logBackend(msg)
                }
            }
            
            let processChunk: (Data) async -> Void = { data in
                guard let chunkStr = String(data: data, encoding: .utf8) else { return }
                lineBuffer += chunkStr
                let parts = lineBuffer.components(separatedBy: .newlines)
                if parts.count > 1 {
                    for line in parts.dropLast() {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            await handleJSONLine(trimmed)
                        }
                    }
                    lineBuffer = parts.last ?? ""
                }
            }
            
            while proc.isRunning {
                let data = handle.availableData
                if data.isEmpty { usleep(50000); continue }
                await processChunk(data)
            }
            
            let remaining = handle.readDataToEndOfFile()
            if !remaining.isEmpty {
                await processChunk(remaining)
            }
            let finalLine = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalLine.isEmpty {
                await handleJSONLine(finalLine)
            }
            
            proc.waitUntilExit()
            errPipe.fileHandleForReading.readabilityHandler = nil
            let exitCode = proc.terminationStatus
            
            await MainActor.run {
                self.isFlashing = false
                if exitCode == 0 && self.errorMessage == nil {
                    self.progress = 1.0
                    self.setStatus("Passcode theme applied successfully!")
                    self.showSuccessAlert = true
                    self.log("Passcode theme '%@' successfully flashed!", theme.name)
                    DeviceProfileStore.recordPasscode(udid: udid, theme: theme.name, version: targetVer)
                } else if let err = self.errorMessage {
                    self.setStatus(err)
                    self.log("ERROR: %@", err)
                } else {
                    self.setStatus("Flashing failed (exit code %@)", "\(exitCode)")
                    self.log("ERROR: %@", self.localizedStatus)
                }
            }
        }
    }
    
    // MARK: - Theme Creator Methods
    
    var effectiveCreatorKeys: [String: NSImage] {
        if creatorSubMode == .posterSlice {
            return creatorSlicedKeys
        } else {
            return creatorCustomKeys
        }
    }
    
    func updatePosterSlicing() {
        guard let img = creatorPosterImage else {
            creatorSlicedKeys = [:]
            return
        }
        creatorSlicedKeys = KeypadSlicer.slicePoster(
            image: img,
            zoom: creatorPosterZoom,
            offset: creatorPosterOffset,
            maskToCircles: creatorMaskToCircles
        )
    }
    
    func loadDefaultPoster(announce: Bool = true) {
        let name = "DefaultPasscodePoster.png"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/\(name)"),
        ].compactMap { $0 }
        guard let image = candidates.compactMap({ NSImage(contentsOf: $0) }).first else {
            if announce { errorMessage = L("Could not load the Chinese numeral example.") }
            return
        }
        creatorSubMode = .posterSlice
        creatorPosterImage = image
        creatorPosterZoom = 1.0
        creatorPosterOffset = .zero
        creatorMaskToCircles = true
        creatorUsesDefaultPoster = true
        updatePosterSlicing()
        if announce { setStatus("Chinese numeral example loaded · Ready to export or flash") }
    }

    func setPosterImage(_ img: NSImage) {
        creatorPosterImage = img
        creatorUsesDefaultPoster = false
        creatorPosterZoom = 1.0
        creatorPosterOffset = .zero
        updatePosterSlicing()
        setStatus("Poster image loaded · Ready to frame and slice")
    }
    
    func setIndividualKey(digit: String, image: NSImage) {
        creatorRawIndividualImages[digit] = image
        creatorIndividualOffsets[digit] = .zero
        creatorIndividualZooms[digit] = 1.0
        selectedKeyDigit = digit
        updateIndividualKey(digit: digit)
        setStatus("Updated key %@ · Drag on dialer to reposition or use zoom slider", digit)
    }
    
    func updateIndividualKey(digit: String) {
        guard let raw = creatorRawIndividualImages[digit] else { return }
        let offset = creatorIndividualOffsets[digit] ?? .zero
        let zoom = creatorIndividualZooms[digit] ?? 1.0
        if let cropped = KeypadSlicer.cropToCircle(
            image: raw,
            targetSize: CGSize(width: 225, height: 225),
            circleDiameter: 222.0,
            zoom: zoom,
            offset: offset
        ) {
            creatorCustomKeys[digit] = cropped
        }
    }
    
    func clearIndividualKey(digit: String) {
        creatorCustomKeys.removeValue(forKey: digit)
        creatorRawIndividualImages.removeValue(forKey: digit)
        creatorIndividualOffsets.removeValue(forKey: digit)
        creatorIndividualZooms.removeValue(forKey: digit)
        if selectedKeyDigit == digit {
            selectedKeyDigit = nil
        }
        setStatus("Cleared key %@", digit)
    }
    
    func clearAllIndividualKeys() {
        creatorCustomKeys.removeAll()
        creatorRawIndividualImages.removeAll()
        creatorIndividualOffsets.removeAll()
        creatorIndividualZooms.removeAll()
        selectedKeyDigit = nil
        setStatus("Cleared all custom keys")
    }
    
    func adoptPosterSlicesToIndividualKeys() {
        for (k, v) in creatorSlicedKeys {
            creatorCustomKeys[k] = v
            creatorRawIndividualImages[k] = v
            creatorIndividualOffsets[k] = .zero
            creatorIndividualZooms[k] = 1.0
        }
        setStatus("Adopted poster slices to individual keys")
    }
    
    func editLoadedThemeInCreator() {
        guard let theme = loadedPasscodeTheme else { return }
        creatorUsesDefaultPoster = false
        for (digit, img) in theme.keysPreview {
            creatorCustomKeys[digit] = img
            creatorRawIndividualImages[digit] = img
            creatorIndividualOffsets[digit] = .zero
            creatorIndividualZooms[digit] = 1.0
        }
        selectedKeyDigit = nil
        creatorSubMode = .individualKeys
        passcodeTabMode = .themeCreator
        setStatus("Loaded '%@' into Theme Creator (%@ keys ready to edit)", theme.name, "\(theme.keysPreview.count)")
        log("Imported theme '%@' into Creator for custom editing", theme.name)
    }
    
    func clearCreator() {
        creatorPosterImage = nil
        creatorUsesDefaultPoster = false
        creatorPosterZoom = 1.0
        creatorPosterOffset = .zero
        creatorSlicedKeys.removeAll()
        clearAllIndividualKeys()
        setStatus("Theme Creator reset")
    }
    
    func flashCreatedTheme() {
        let keys = effectiveCreatorKeys
        guard !keys.isEmpty else {
            errorMessage = L("Please add at least one key icon or import a poster image first.")
            return
        }
        guard let dev = device, dev.isUSBConnectedIPhone else {
            errorMessage = L("Connect your iPhone with USB to write a passcode theme.")
            return
        }
        
        guard let stagedURL = PasscodeThemeExporter.stageTemporaryTheme(
            keys: keys,
            language: passcodeLanguageTarget,
            boldMode: passcodeBoldTarget
        ) else {
            errorMessage = L("Failed to package theme for flashing.")
            return
        }
        
        let themeInfo = PasscodeThemeInfo(
            name: L("Created Theme"),
            filePath: stagedURL.path,
            detectedVersion: targetTelephonyVersion,
            supportedVersions: [],
            fileCount: keys.count * 4,
            keysPreview: keys
        )
        self.loadedPasscodeTheme = themeInfo
        self.flashPasscodeTheme()
    }

    func restoreDefaultPasscode() {
        guard let dev = device, dev.isUSBConnectedIPhone, let udid = dev.udid,
              let version = dev.passcodeCacheVersion else {
            errorMessage = L("Connect a supported iPhone with USB to restore the default passcode.")
            return
        }
        guard udid == activeProfileUDID else {
            errorMessage = L("The card list is switching to the connected iPhone. Try again in a moment.")
            return
        }
        guard !isFlashing && !isPullingSkins else { return }

        isFlashing = true
        didClearPasscodeCache = false
        errorMessage = nil
        showLogs = true
        progress = 0
        setStatus("Clearing custom passcode cache...")
        let scriptDir = self.scriptDir

        Task.detached {
            let process = Process()
            process.executableURL = AppViewModel.pythonExecutableURL
            process.environment = AppViewModel.processEnvironment
            process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            process.arguments = ["facelift_backend.py", "--restore-default-passcode", udid, version]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            var succeeded = false
            var detail = ""
            var backupPath = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let line = String(data: data, encoding: .utf8)?.split(separator: "\n").last,
                   let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                    succeeded = process.terminationStatus == 0 && (json["ok"] as? Bool) == true
                    detail = json["error"] as? String ?? ""
                    backupPath = json["backup"] as? String ?? ""
                }
            } catch {
                detail = error.localizedDescription
            }

            let result = succeeded
            let failureDetail = detail
            let savedBackup = backupPath
            await MainActor.run {
                self.isFlashing = false
                if result {
                    self.progress = 1
                    self.loadedPasscodeTheme = nil
                    self.didClearPasscodeCache = true
                    self.setStatus("Passcode cache cleared. Restart your iPhone.")
                    if !savedBackup.isEmpty {
                        self.log("Passcode cache backup saved at %@.", savedBackup)
                    }
                    self.showSuccessAlert = true
                } else {
                    self.errorMessage = L("Could not restore the default passcode. Check the log.")
                    self.setStatus("Could not restore the default passcode. Check the log.")
                    self.log("Passcode reset failed: %@", failureDetail)
                }
            }
        }
    }
}

// MARK: - Card View Component (Apple Wallet Style)
