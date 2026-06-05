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
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRowLocal(
                        title: "Capture eval samples",
                        subtitle: "Save every successful extraction (image + model output) for offline labeling.",
                        isOn: $enabled
                    )
                    if enabled {
                        banner
                    }
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

    private var banner: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text("Eval capture is ON — every successful extraction will be saved.")
                .font(Theme.Typography.sans(12, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.chipRadius)
                .fill(Theme.Palette.dangerBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.chipRadius)
                .stroke(Theme.Palette.danger.opacity(0.35), lineWidth: 1)
        )
    }

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
        HStack(spacing: 10) {
            Button {
                Task { await exportSamples() }
            } label: {
                exporting ? AnyView(ProgressView()) : AnyView(Text("Export samples"))
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(snapshot.sampleCount == 0 || exporting)

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Text("Clear samples")
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(snapshot.sampleCount == 0)
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

private struct ToggleRowLocal: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.sans(11))
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

extension EvalSampleWriter.DirSnapshot {
    static var empty: EvalSampleWriter.DirSnapshot {
        .init(sampleCount: 0, totalBytes: 0, lastWrite: nil)
    }
}

#endif
