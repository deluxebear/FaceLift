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
                DeviceSidebarRow(device: vm.device)
                    .tag(WorkspaceSection.device)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DeviceSidebarRow: View {
    let device: DeviceInfo?

    var body: some View {
        let connected = device?.connected == true
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
                    .foregroundStyle(connected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if connected {
                    Text("iOS \(device?.version ?? "") · \(device?.isWiFi == true ? L("Wi-Fi") : L("USB"))")
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
