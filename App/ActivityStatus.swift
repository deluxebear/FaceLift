import SwiftUI
import AppKit

/// Toolbar-center status: status text when idle, progress while busy.
/// Clicking it opens the activity log.
struct ActivityStatusView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        Button { vm.showLogs.toggle() } label: {
            HStack(spacing: 8) {
                if vm.isBusy || vm.isCheckingDevice {
                    ProgressView().controlSize(.small)
                } else {
                    Circle()
                        .fill(deviceStatusColor(vm.device))
                        .frame(width: 7, height: 7)
                }
                Text(vm.localizedStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if vm.isFlashing {
                    Text("\(Int(vm.progress * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 180, idealWidth: 320, maxWidth: 420)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Show Activity Log"))
        .popover(isPresented: $vm.showLogs, arrowEdge: .bottom) {
            ActivityLogPopover(vm: vm)
        }
    }
}

struct ActivityLogPopover: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Activity Log")).font(.headline)
                Spacer()
                Button(L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.logs.map(\.display).joined(separator: "\n"), forType: .string)
                }
                .disabled(vm.logs.isEmpty)
                Button(L("Clear")) { vm.logs.removeAll() }
                    .disabled(vm.logs.isEmpty)
            }
            if vm.logs.isEmpty {
                Text(L("No activity yet."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(vm.logs) { line in
                                Text(line.display)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: vm.logs.count) { _, _ in scrollToEnd(proxy) }
                }
            }
        }
        .padding(14)
        .frame(width: 520, height: 320)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = vm.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}
