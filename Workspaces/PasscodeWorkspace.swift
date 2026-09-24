import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var passcodeWorkspace: some View {
        ScrollView {
            passcodeThemeWorkspaceView
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}

extension ContentView {
    
    var passcodeThemeWorkspaceView: some View {
        passcodeThemeCreatorWorkspaceView
    }
    
    
    
    
    
    
}

extension ContentView {
    func openPasscodeThemePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "passthm") ?? .data,
            UTType(filenameExtension: "passtheme") ?? .data,
            .zip
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a .passthm passcode theme package...")
        if panel.runModal() == .OK, let url = panel.url {
            vm.inspectPasscodeTheme(url: url)
        }
    }
    
    func openPosterPicker() {
        let panel = NSOpenPanel()
        panel.title = L("Choose Poster Image")
        panel.message = L("Select a wallpaper or photo to slice for the passcode keypad...")
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "heic") ?? .image,
            UTType(filenameExtension: "webp") ?? .image,
            .image
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            vm.setPosterImage(img)
        }
    }
    
    func openIndividualKeyPicker(for digit: String) {
        let panel = NSOpenPanel()
        panel.title = L("Choose Icon for Key %@", digit)
        panel.message = L("Select an icon or image for key %@...", digit)
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "heic") ?? .image,
            UTType(filenameExtension: "webp") ?? .image,
            .image
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            vm.setIndividualKey(digit: digit, image: img)
        }
    }
    
    func openSavePasscodeThemePanel() {
        let keys = vm.effectiveCreatorKeys
        guard !keys.isEmpty else {
            vm.errorMessage = L("Please configure at least one key before exporting.")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = L("Save Passcode Theme")
        panel.prompt = L("Export")
        panel.allowedContentTypes = [UTType(filenameExtension: "passthm") ?? .data]
        panel.nameFieldStringValue = "CustomTheme"
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try PasscodeThemeExporter.exportTheme(keys: keys, targetURL: url)
                vm.setStatus("Theme exported successfully to %@", url.lastPathComponent)
                vm.log("Exported .passthm to %@", url.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                vm.errorMessage = L("Failed to export theme: %@", error.localizedDescription)
            }
        }
    }
    
    func handlePosterDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        loadImage(from: provider) { img in
            if let img = img {
                vm.setPosterImage(img)
            }
        }
        return true
    }
    
    func handleThemeDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url else { return }
            Task { @MainActor in vm.inspectPasscodeTheme(url: url) }
        }
        return true
    }

    func handleIndividualKeyDrop(digit: String, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        loadImage(from: provider) { img in
            if let img = img {
                vm.setIndividualKey(digit: digit, image: img)
            }
        }
        return true
    }
    
    func loadImage(from provider: NSItemProvider, completion: @escaping (NSImage?) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, let img = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { completion(img) }
                    return
                }
                if provider.canLoadObject(ofClass: NSImage.self) {
                    _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                        DispatchQueue.main.async { completion(img as? NSImage) }
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                DispatchQueue.main.async { completion(img as? NSImage) }
            }
        } else {
            completion(nil)
        }
    }
}
