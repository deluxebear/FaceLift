import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var deviceWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 51))
                        .foregroundStyle(FaceLiftPalette.blue)
                        .frame(width: 95, height: 110)
                        .background(Color(red: 0.90, green: 0.94, blue: 1), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.device?.connected == true ? (vm.device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(FaceLiftPalette.ink)
                        Text(vm.device?.connected == true ? "\(vm.device?.product ?? "iPhone") · iOS \(vm.device?.version ?? "")" : L("Connect your iPhone with a USB cable and trust this Mac."))
                            .foregroundStyle(FaceLiftPalette.muted)
                        Label(vm.device?.connected == true ? (vm.device?.isWiFi == true ? L("Connected via Wi-Fi") : L("Connected via USB")) : L("Waiting for device"), systemImage: vm.device?.connected == true ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(vm.device?.connected == true ? Color.green : FaceLiftPalette.muted)
                    }
                    Spacer()
                    Button { vm.checkDevice() } label: { Label(L("Refresh device connection"), systemImage: "arrow.clockwise") }
                        .faceLiftProminentButton()
                        .tint(FaceLiftPalette.blue)
                        .disabled(vm.isCheckingDevice)
                }
                .padding(22)
                .faceLiftWorkspacePanel(cornerRadius: 18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(FaceLiftPalette.line))

                VStack(alignment: .leading, spacing: 14) {
                    Text(L("How to connect"))
                        .font(.system(size: 17, weight: .bold))
                    instructionRow("1", L("Connect iPhone to your Mac with USB."))
                    instructionRow("2", L("Unlock iPhone and tap Trust This Computer."))
                    instructionRow("3", L("For card scanning, open Apple Pay and tap each card."))
                    if vm.device?.isWiFi == true {
                        Label(L("Reading card artwork requires USB. Reconnect with a cable."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .faceLiftWorkspacePanel(cornerRadius: 18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(FaceLiftPalette.line))
            }
            .padding(26)
        }
    }
}
