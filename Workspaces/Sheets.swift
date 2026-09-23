import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FaceLiftPalette.blue)
                .frame(width: 27, height: 27)
                .background(Color(red: 0.90, green: 0.94, blue: 1), in: Circle())
            Text(text)
                .foregroundStyle(FaceLiftPalette.ink)
        }
    }
}

extension ContentView {
    var guideSheet: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L("FaceLift Guide")).font(.title2.bold())
                Spacer()
                Button(L("Close")) { showGuide = false }
            }
            instructionRow("1", L("Connect iPhone to your Mac with USB."))
            instructionRow("2", L("Scan Wallet cards, or add a card hash manually."))
            instructionRow("3", L("Choose artwork, select cards, then write the skins."))
            Divider()
            instructionRow("4", L("Import a passcode theme or create one from images."))
            instructionRow("5", L("Review the preview and write the theme to iPhone."))
        }
        .padding(25)
        .frame(width: 510)
    }
    
}

extension ContentView {
    var creditsSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            
            Text("FaceLift")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(L("Apple Wallet Skins & Passcode Themes for iOS 18+"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.green)
                    Text(L("Developer & Maintainer:"))
                        .fontWeight(.medium)
                    Link("@jetems", destination: URL(string: "https://github.com/jetems")!)
                }
                
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.blue)
                    Text(L("AirCard Author:"))
                        .fontWeight(.medium)
                    Link("@mak5er", destination: URL(string: "https://github.com/mak5er")!)
                    Text("·")
                        .foregroundColor(.secondary)
                    Link("Twitter / X", destination: URL(string: "https://x.com/mak5er")!)
                }
                
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.blue)
                    Text(L("AirCard Contributor:"))
                        .fontWeight(.medium)
                    Link("@Lumid-Off", destination: URL(string: "https://github.com/Lumid-Off")!)
                    Text("·")
                        .foregroundColor(.secondary)
                    Link("Twitter / X", destination: URL(string: "https://x.com/LumidOff")!)
                }
                
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.teal)
                    Text(L("Based on:"))
                        .fontWeight(.medium)
                    Link("AirCard v1.2.3", destination: URL(string: "https://github.com/mak5er/AirCard")!)
                    Text(L("(MIT License)") )
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.orange)
                    Text(L("Core Exploit:"))
                        .fontWeight(.medium)
                    Text(L("airlift (AirTraffic sync escape)"))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(FaceLiftPalette.blue)
                    Text(L("Passcode Themes:"))
                        .fontWeight(.medium)
                    Text(L(".passthm standard (Cowabunga / Nugget)"))
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            
            Divider()
            
            Button(L("Close")) {
                showCredits = false
            }
            .faceLiftProminentButton()
            .controlSize(.regular)
        }
        .padding(24)
        .frame(width: 420)
    }
    
    var addCardSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Add Card Hashes Manually"))
                .font(.headline)
            Text(L("Paste one or more card hashes (separated by spaces, commas, or newlines):"))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text(L("Use a hash previously scanned by FaceLift or saved in a card backup. Adding a hash only saves it to this list; it does not create or verify a card on your iPhone."))
            }
            .font(.caption)
            .foregroundStyle(FaceLiftPalette.muted)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FaceLiftPalette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            
            TextEditor(text: $vm.manualHashInput)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if !manualHashFeedback.isEmpty {
                Text(manualHashFeedback)
                    .font(.caption)
                    .foregroundStyle(FaceLiftPalette.blue)
            }
            
            HStack {
                Button(L("Cancel")) {
                    vm.showAddCardSheet = false
                    vm.manualHashInput = ""
                    manualHashFeedback = ""
                }
                .faceLiftSecondaryButton()
                .controlSize(.regular)
                
                Spacer()
                
                Button(L("Add to List")) {
                    let result = vm.addCardHash(vm.manualHashInput)
                    if result.rejected.isEmpty {
                        vm.showAddCardSheet = false
                        vm.manualHashInput = ""
                        manualHashFeedback = ""
                    } else {
                        vm.manualHashInput = result.rejected.joined(separator: "\n")
                        manualHashFeedback = result.added > 0
                            ? L("Added %@ card hash(es). Invalid or duplicate entries remain below.", "\(result.added)")
                            : L("No card hashes were added. Check the format or remove duplicates.")
                    }
                }
                .faceLiftProminentButton()
                .controlSize(.regular)
                .disabled(vm.manualHashInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 440)
    }
    
}
