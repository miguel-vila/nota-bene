#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

extension SettingsView {
    @ViewBuilder
    var developerSection: some View {
        SettingsDeveloperSection()
    }
}

struct SettingsDeveloperSection: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(EvalPreferenceKey.evalCaptureEnabled) private var enabled: Bool = false
    @State private var snapshot: EvalSampleWriter.DirSnapshot = .empty
    @State private var showingClearConfirm: Bool = false
    @State private var exportError: String?
    @State private var exporting: Bool = false
    @State private var shareItem: ShareItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("DEVELOPER")
            ThemedCard {
                ToggleRow(
                    title: "Show response payload on errors",
                    subtitle: "Includes raw HTTP body in error messages",
                    isOn: $state.debugMode
                )
            }
            ThemedCard {
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(
                        title: "Capture eval samples",
                        subtitle: "Adds a per-capture “Save eval sample” toggle on the Review screen, so you choose which extractions to keep.",
                        isOn: $enabled
                    )
                    statusFooter
                    actions
                }
                .padding(.vertical, 4)
            }
            if let exportError {
                Text(exportError)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
        .task { await refresh() }
        .onChange(of: enabled) { _, _ in Task { await refresh() } }
        .sheet(item: $shareItem, onDismiss: { Task { await refresh() } }) { item in
            ActivityShareSheet(items: [item.url], onComplete: {
                try? FileManager.default.removeItem(at: item.url)
            })
        }
        .alert("Clear all samples?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    try? await EvalSampleWriter.shared.clearAll()
                    await refresh()
                }
            }
        } message: {
            Text("This deletes \(snapshot.sampleCount) sample(s) and their request templates from this device. Cannot be undone.")
        }
    }

    // MARK: - Pieces

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countLine)
                .font(Theme.Typography.mono(11))
                .tracking(0.4)
                .foregroundStyle(Theme.Palette.muted)
            if let last = snapshot.lastWrite {
                Text(lastWriteLine(last))
                    .font(Theme.Typography.sans(11))
                    .foregroundStyle(last.succeeded ? Theme.Palette.muted : Theme.Palette.danger)
            }
        }
    }

    private var actions: some View {
        let hasSamples = snapshot.sampleCount > 0
        return HStack(spacing: 10) {
            Button {
                Task { await exportSamples() }
            } label: {
                exporting
                    ? AnyView(ProgressView().tint(Theme.Palette.bg))
                    : AnyView(Text("Export samples"))
            }
            .buttonStyle(PrimaryButtonStyle(
                height: Theme.Layout.secondaryButtonHeight,
                enabled: hasSamples && !exporting
            ))
            .disabled(!hasSamples || exporting)

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Text("Clear samples")
            }
            .buttonStyle(SecondaryButtonStyle(foreground: Theme.Palette.danger, enabled: hasSamples))
            .disabled(!hasSamples)
        }
    }

    private var countLine: String {
        let mb = Double(snapshot.totalBytes) / (1024.0 * 1024.0)
        let mbString = String(format: "%.1f", mb)
        return "\(snapshot.sampleCount) sample\(snapshot.sampleCount == 1 ? "" : "s") · ~\(mbString) MB on disk"
    }

    private func lastWriteLine(_ last: EvalSampleWriter.LastWrite) -> String {
        let when = Self.timeFormatter.string(from: last.timestamp)
        if last.succeeded {
            return "Last write: \(when)"
        } else {
            return "Last write failed (\(when)): \(last.message ?? "unknown error")"
        }
    }

    // MARK: - Actions

    private func refresh() async {
        let snap = await EvalSampleWriter.shared.snapshot()
        await MainActor.run { self.snapshot = snap }
    }

    private func exportSamples() async {
        exporting = true
        defer { exporting = false }
        do {
            let url = try await EvalSampleWriter.shared.exportZip()
            await MainActor.run {
                self.exportError = nil
                self.shareItem = ShareItem(url: url)
            }
        } catch {
            await MainActor.run { self.exportError = "Export failed: \(error)" }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension EvalSampleWriter.DirSnapshot {
    static var empty: EvalSampleWriter.DirSnapshot {
        .init(sampleCount: 0, totalBytes: 0, lastWrite: nil)
    }
}

#endif
