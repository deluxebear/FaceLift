import SwiftUI

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
                        Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
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

    private func deviceSubtitle(_ device: DeviceInfo?) -> String {
        guard device?.connected == true else { return L("Waiting for device") }
        let via = device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")
        return "iOS \(device?.version ?? "—") · \(via)"
    }
}
