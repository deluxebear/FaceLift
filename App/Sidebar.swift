import SwiftUI

struct SidebarView: View {
    @ObservedObject var vm: AppViewModel
    @Binding var selection: WorkspaceSection

    var body: some View {
        List(selection: Binding<WorkspaceSection?>(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )) {
            Section(L("Customize")) {
                ForEach(WorkspaceSection.customize, id: \.self) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            Section(L("Device")) {
                DeviceSidebarRow(
                    device: vm.device,
                    name: vm.connectedDeviceName,
                    offlineProfileName: vm.activeProfileUDID == nil || vm.isActiveDeviceConnected ? nil : vm.activeProfileName
                )
                    .tag(WorkspaceSection.device)
                    .contextMenu {
                        // Several iPhones connected: pick which one FaceLift works with.
                        if let available = vm.device?.available, available.count > 1 {
                            ForEach(available) { item in
                                Button {
                                    vm.useConnectedDevice(item.udid)
                                } label: {
                                    if vm.device?.udid == item.udid {
                                        Label(vm.displayName(for: item.udid), systemImage: "checkmark")
                                    } else {
                                        Text(vm.displayName(for: item.udid))
                                    }
                                }
                                .disabled(vm.isBusy || vm.device?.udid == item.udid)
                            }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.sidePanelBackground)
    }
}

private struct DeviceSidebarRow: View {
    let device: DeviceInfo?
    let name: String
    /// The iPhone whose cards are shown while it is not the connected one.
    let offlineProfileName: String?

    var body: some View {
        let connected = device?.connected == true
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(connected ? name : L("No iPhone connected"))
                    .foregroundStyle(connected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if connected {
                    Text("iOS \(device?.version ?? "") · \(device?.isWiFi == true ? L("Wi-Fi") : L("USB"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let offlineProfileName {
                    Text(L("Showing cards of %@", offlineProfileName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "iphone")
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(deviceStatusColor(device))
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: 2)
                }
        }
    }
}
