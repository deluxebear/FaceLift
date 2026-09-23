import SwiftUI

extension ContentView {
    var deviceWorkspace: some View {
        let device = vm.device
        let connected = device?.connected == true
        return Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "iphone")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connected ? (device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.title3.weight(.semibold))
                        Label(
                            connected ? (device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")) : L("Waiting for device"),
                            systemImage: connected ? "checkmark.circle.fill" : "circle.dotted"
                        )
                        .font(.callout)
                        .foregroundStyle(connected ? deviceStatusColor(device) : Color.secondary)
                    }
                }
                .padding(.vertical, 4)
                if connected {
                    LabeledContent(L("Model"), value: device?.product ?? "iPhone")
                    LabeledContent(L("iOS Version"), value: device?.version ?? "")
                }
            }
            if connected && device?.isWiFi == true {
                Section {
                    Label(L("Reading card artwork requires USB. Reconnect with a cable."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section(L("How to connect")) {
                instructionRow("1", L("Connect iPhone to your Mac with USB."))
                instructionRow("2", L("Unlock iPhone and tap Trust This Computer."))
                instructionRow("3", L("For card scanning, open Apple Pay and tap each card."))
            }
        }
        .formStyle(.grouped)
    }
}
