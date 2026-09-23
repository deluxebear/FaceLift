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
    @Published var passcodeLanguageTarget: PasscodeLanguageTarget = .all
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
    private var skinPullQueue: [String] = []
    
    private var scanProcess: Process?
    private let scriptDir: String
    private let storageKey = "jetems.facelift.savedCards"
    private let legacyStorageKey0 = "mak5er.aircard.savedCards"
    private let legacyStorageKey1 = "mak5er.savedCards"
    private let legacyStorageKey2 = "LumiCards.savedCards"
    
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
        
        loadSavedCards()
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
    
    // MARK: - Persistence
    
    func loadSavedCards() {
        var loaded: [String] = []
        
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey), !saved.isEmpty {
            loaded.append(contentsOf: saved)
        } else if let saved = UserDefaults.standard.stringArray(forKey: legacyStorageKey0), !saved.isEmpty {
            loaded.append(contentsOf: saved)
        } else if let saved = UserDefaults.standard.stringArray(forKey: legacyStorageKey1), !saved.isEmpty {
            loaded.append(contentsOf: saved)
        } else if let saved = UserDefaults.standard.stringArray(forKey: legacyStorageKey2), !saved.isEmpty {
            loaded.append(contentsOf: saved)
        }
        
        for p in ["~/.facelift_cards.json", "~/.aircard_cards.json", "~/.lumicards_cards.json"] {
            let jsonPath = NSString(string: p).expandingTildeInPath
            if let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
               let jsonHashes = try? JSONDecoder().decode([String].self, from: data) {
                for h in jsonHashes where !loaded.contains(h) {
                    loaded.append(h)
                }
            }
        }
        
        let dummyHashes = [
            "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
            "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
            "hwAtAmHKYwsQrJbT5cTNDsaxVME="
        ]
        loaded.removeAll { dummyHashes.contains($0) || ($0.contains("-") && $0.count == 36) }
        
        self.cards = loaded.map { id in
            var card = CardItem(id: id, isSelected: true)
            let stored = Self.storedSkinURL(for: id)
            if FileManager.default.fileExists(atPath: stored.path),
               let image = NSImage(contentsOf: stored) {
                card.customImageURL = stored
                card.customImage = image
            }
            return card
        }
        log("Loaded %@ real card(s) from storage.", "\(cards.count)")
    }

    static func storedSkinURL(for cardId: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("FaceLift/skins", isDirectory: true)
        // One-time migration of skins saved under the previous AirCard branding.
        let legacyBase = support.appendingPathComponent("AirCard/skins", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path),
           FileManager.default.fileExists(atPath: legacyBase.path) {
            try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacyBase, to: base)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let allowed = CharacterSet(charactersIn: "-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+=")
        let safe = cardId.unicodeScalars.allSatisfy { allowed.contains($0) } ? cardId : "card"
        return base.appendingPathComponent(safe).appendingPathExtension("png")
    }

    func storeSkin(for cardId: String, url: URL) {
        guard let idx = cards.firstIndex(where: { $0.id == cardId }) else { return }
        let dest = Self.storedSkinURL(for: cardId)
        if url.path != dest.path {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        let stored = FileManager.default.fileExists(atPath: dest.path) ? dest : url
        cards[idx].customImageURL = stored
        cards[idx].customImage = NSImage(contentsOf: stored)
        cards[idx].isSelected = true
    }

    func queueSkinPulls(ids: [String], replacingStored: Bool) {
        guard device?.connected == true, let _ = device?.udid, !isFlashing else { return }
        if device?.isWiFi == true {
            setStatus("Reading artwork over Wi-Fi may fail — connect via USB.")
            log("Warning: reading artwork over Wi-Fi is unreliable; use a USB connection.")
        }
        for id in ids {
            let stored = Self.storedSkinURL(for: id)
            let hasStored = FileManager.default.fileExists(atPath: stored.path)
            if !replacingStored && hasStored { continue }
            if !skinPullQueue.contains(id) {
                skinPullQueue.append(id)
            }
        }
        pumpSkinPulls()
    }

    func pumpSkinPulls() {
        guard !isPullingSkins, !isFlashing, let udid = device?.udid else { return }
        guard !skinPullQueue.isEmpty else { return }
        let cardId = skinPullQueue.removeFirst()
        isPullingSkins = true
        setStatus("Reading artwork from iPhone...")
        let scriptDir = self.scriptDir
        let dest = Self.storedSkinURL(for: cardId)
        Task.detached {
            let process = Process()
            process.executableURL = AppViewModel.pythonExecutableURL
            process.environment = AppViewModel.processEnvironment
            process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            process.arguments = ["facelift_backend.py", "--pull-card", udid, cardId, dest.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            let pulled: (ok: Bool, asset: String, reason: String)
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    pulled = ((json["ok"] as? Bool) == true, json["asset"] as? String ?? "", json["reason"] as? String ?? "")
                } else {
                    pulled = (false, "", "sync")
                }
            } catch {
                pulled = (false, "", "sync")
            }
            await MainActor.run {
                self.isPullingSkins = false
                if pulled.ok, let image = NSImage(contentsOf: dest) {
                    if let idx = self.cards.firstIndex(where: { $0.id == cardId }) {
                        self.cards[idx].customImageURL = dest
                        self.cards[idx].customImage = image
                    }
                    self.setStatus("Read artwork for %@.", String(cardId.prefix(8)))
                    self.log("Read %@ artwork for card %@.", pulled.asset, String(cardId.prefix(8)))
                } else if pulled.reason == "sync" {
                    self.skinPullQueue.removeAll()
                    self.setStatus("Could not read artwork from iPhone.")
                    self.log("Could not read artwork from iPhone.")
                } else {
                    self.log("No artwork found on iPhone for %@.", String(cardId.prefix(8)))
                    if self.skinPullQueue.isEmpty {
                        self.setStatus("No artwork found on iPhone for %@.", String(cardId.prefix(8)))
                    }
                }
                self.pumpSkinPulls()
            }
        }
    }
    
    func saveCards() {
        let hashes = cards.map { $0.id }
        UserDefaults.standard.set(hashes, forKey: storageKey)
        
        let jsonPath = NSString(string: "~/.facelift_cards.json").expandingTildeInPath
        if let data = try? JSONEncoder().encode(hashes) {
            try? data.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
        }
    }
    
    func addCardHash(_ raw: String) -> (added: Int, rejected: [String]) {
        let components = raw.components(separatedBy: CharacterSet(charactersIn: " \n\r\t,;"))
        var addedCount = 0
        var rejected: [String] = []
        for comp in components {
            let clean = comp.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let validHash = clean.range(of: "^[-A-Za-z0-9_+=]{16,64}$", options: .regularExpression) != nil
            if validHash && !cards.contains(where: { $0.id == clean }) {
                cards.append(CardItem(id: clean, isSelected: true))
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
            try? FileManager.default.removeItem(at: Self.storedSkinURL(for: cardId))
            log("Cleared custom skin for: %@...", String(cardId.prefix(12)))
        }
    }
    
    // MARK: - Device Connection
    
    func checkDevice(silent: Bool = false) {
        guard !isCheckingDevice else { return }
        isCheckingDevice = true
        if !silent { setStatus("Checking connected devices...") }
        let scriptDir = self.scriptDir
        
        Task.detached {
            let process = Process()
            process.executableURL = AppViewModel.pythonExecutableURL
            process.environment = AppViewModel.processEnvironment
            process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)
            process.arguments = ["facelift_backend.py", "--device"]
            
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
        guard let udid = device?.udid else {
            errorMessage = L("No iPhone connected.")
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
        proc.standardError = FileHandle.nullDevice
        
        self.scanProcess = proc
        
        let dummyHashes = [
            "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
            "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
            "hwAtAmHKYwsQrJbT5cTNDsaxVME="
        ]
        
        Task.detached {
            do {
                try proc.run()
                let handle = pipe.fileHandleForReading
                var buffer = Data()
                
                while proc.isRunning {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        usleep(100000)
                        continue
                    }
                    buffer.append(chunk)
                    
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                        
                        guard let line = String(data: lineData, encoding: .utf8) else { continue }
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
                                        if !self.cards.contains(where: { $0.id == candidate }) {
                                            self.cards.append(CardItem(id: candidate, isSelected: true))
                                            self.saveCards()
                                            self.log("Found card: %@", candidate)
                                            self.queueSkinPulls(ids: [candidate], replacingStored: false)
                                            NSSound(named: "Glass")?.play()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.log("Syslog monitor stopped: %@", error.localizedDescription)
                    self.isScanningCards = false
                }
            }
        }
    }
    
    func stopCardScanning() {
        scanProcess?.terminate()
        scanProcess = nil
        isScanningCards = false
        dismissScanPrompt()
        saveCards()
        log("Scanning stopped. Total cards: %@.", "\(cards.count)")
    }
    
    // MARK: - Skin Application
    
    func applySkin() {
        guard let udid = device?.udid else {
            errorMessage = L("No iPhone connected.")
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
