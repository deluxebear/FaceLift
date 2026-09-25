import SwiftUI
import AppKit

extension ContentView {
    var deviceWorkspace: some View {
        let device = vm.device
        let connected = device?.connected == true
        return Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(deviceStatusColor(device))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                                .offset(x: 4, y: 2)
                        }
                        .frame(width: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connected ? vm.connectedDeviceName : L("No iPhone connected"))
                            .font(.title3.weight(.semibold))
                        Text(deviceSubtitle(device))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if connected {
                    LabeledContent(L("Model"), value: device?.product ?? "iPhone")
                    LabeledContent(L("iOS Version"), value: device?.version ?? "—")
                    LabeledContent(L("Connection"), value: device?.isWiFi == true ? L("Wi-Fi") : L("USB"))
                }
            }
            if connected && device?.isWiFi == true {
                Section {
                    Label {
                        Text(L("Reading card artwork requires USB. Reconnect with a cable."))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            if let available = device?.available, connected, available.count > 1 {
                Section {
                    ForEach(available) { item in
                        connectedDeviceRow(item)
                    }
                } header: {
                    Text(L("Connected iPhones"))
                } footer: {
                    Text(L("FaceLift works with one iPhone at a time. Cards and artwork are kept separately for each."))
                }
            }
            if !vm.knownDevices.isEmpty {
                Section {
                    ForEach(vm.knownDevices.sorted { ($0.lastSeen ?? "") > ($1.lastSeen ?? "") }) { record in
                        knownDeviceRow(record)
                    }
                } header: {
                    Text(L("Known iPhones"))
                } footer: {
                    Text(L("You can view any iPhone's cards here. Writing needs that iPhone connected."))
                }
            }
            Section(L("How to connect")) {
                instructionRow("1", L("Connect iPhone to your Mac with USB."))
                instructionRow("2", L("Unlock iPhone and tap Trust This Computer."))
                instructionRow("3", L("For card scanning, open Apple Pay and tap each card."))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func connectedDeviceRow(_ item: AvailableDevice) -> some View {
        let inUse = vm.device?.udid == item.udid
        return HStack(spacing: 10) {
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.displayName(for: item.udid))
                Text(item.connection == "wifi" ? L("Wi-Fi") : L("USB"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if inUse {
                Label(L("In Use"), systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button(L("Use This iPhone")) { vm.useConnectedDevice(item.udid) }
                    .disabled(vm.isBusy)
            }
        }
    }

    private func knownDeviceRow(_ record: DeviceRecord) -> some View {
        let isConnected = vm.device?.connected == true && vm.device?.udid == record.udid
        let isShown = vm.activeProfileUDID == record.udid
        return HStack(spacing: 10) {
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .overlay(alignment: .bottomTrailing) {
                    if isConnected {
                        Circle()
                            .fill(deviceStatusColor(vm.device))
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 2)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .fontWeight(isShown ? .semibold : .regular)
                Text(knownDeviceDetail(record, isConnected: isConnected, isShown: isShown))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Menu {
                Button(L("Show Its Cards")) { vm.viewProfile(record.udid) }
                    .disabled(isShown || vm.isBusy)
                Button(L("Rename…")) { promptRenameDevice(record) }
                Divider()
                Button(L("Forget This iPhone…"), role: .destructive) { confirmForgetDevice(record) }
                    .disabled(vm.isBusy)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More"))
        }
    }

    private func knownDeviceDetail(_ record: DeviceRecord, isConnected: Bool, isShown: Bool) -> String {
        var parts: [String] = []
        if isConnected { parts.append(L("Connected")) }
        if isShown { parts.append(L("Showing its cards")) }
        if let product = record.product { parts.append(product) }
        if let version = record.lastVersion { parts.append("iOS \(version)") }
        parts.append(L("%@ card(s)", "\(DeviceProfileStore.cardCount(udid: record.udid))"))
        if !isConnected, let seen = record.lastSeen,
           let date = ISO8601DateFormatter().date(from: seen) {
            parts.append(L("Last connected %@", date.formatted(date: .abbreviated, time: .shortened)))
        }
        return parts.joined(separator: " · ")
    }

    private func promptRenameDevice(_ record: DeviceRecord) {
        let alert = NSAlert()
        alert.messageText = L("Rename iPhone")
        alert.informativeText = L("This name is only used in FaceLift. Leave it empty to use the iPhone's own name.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = record.customName ?? ""
        field.placeholderString = record.name ?? "iPhone"
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            vm.renameDevice(record.udid, to: field.stringValue)
        }
    }

    private func confirmForgetDevice(_ record: DeviceRecord) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Forget %@?", record.displayName)
        alert.informativeText = L("This deletes the %@ card(s), saved original artwork and artwork history FaceLift keeps for this iPhone. Nothing on the iPhone changes. Without the saved originals, cards FaceLift has changed can no longer be restored to their original artwork.", "\(DeviceProfileStore.cardCount(udid: record.udid))")
        alert.addButton(withTitle: L("Forget"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            vm.forgetDevice(record.udid)
        }
    }

    private func deviceSubtitle(_ device: DeviceInfo?) -> String {
        guard device?.connected == true else { return L("Waiting for device") }
        let via = device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")
        return "iOS \(device?.version ?? "—") · \(via)"
    }
}
