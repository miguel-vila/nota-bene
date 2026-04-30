#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var geminiInput = ""
    @State private var readwiseInput = ""
    @State private var customModelInput = ""
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var testing: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Gemini") {
                    HStack {
                        Text("Stored").foregroundStyle(.secondary)
                        Spacer()
                        Text(state.geminiKeyMasked.isEmpty ? "Not set" : state.geminiKeyMasked)
                            .font(.system(.body, design: .monospaced))
                    }
                    SecureField("Replace key", text: $geminiInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Gemini key") {
                        save(\.geminiInput, target: .gemini)
                    }
                    .disabled(geminiInput.isEmpty)
                    Button("Test Gemini connection") {
                        Task { await testGemini() }
                    }
                    .disabled(state.geminiKeyMasked.isEmpty || testing)
                    Button("Clear", role: .destructive) {
                        try? state.clearGeminiKey()
                    }
                }

                Section("Gemini model") {
                    Picker("Model", selection: modelSelection) {
                        ForEach(GeminiClient.ModelPreset.allCases) { preset in
                            Text(preset.label).tag(Optional(preset))
                        }
                        Text("Custom…").tag(Optional<GeminiClient.ModelPreset>.none)
                    }
                    if currentPreset == nil {
                        TextField("Model name", text: $customModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { commitCustomModel() }
                        Button("Use this model") { commitCustomModel() }
                            .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Text("Active").foregroundStyle(.secondary)
                        Spacer()
                        Text(state.geminiModel)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button("Reset to default") {
                        state.resetGeminiModelToDefault()
                        customModelInput = ""
                    }
                    .disabled(state.geminiModel == GeminiClient.defaultModel)
                }

                Section("Readwise") {
                    HStack {
                        Text("Stored").foregroundStyle(.secondary)
                        Spacer()
                        Text(state.readwiseKeyMasked.isEmpty ? "Not set" : state.readwiseKeyMasked)
                            .font(.system(.body, design: .monospaced))
                    }
                    SecureField("Replace key", text: $readwiseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Readwise key") {
                        save(\.readwiseInput, target: .readwise)
                    }
                    .disabled(readwiseInput.isEmpty)
                    Button("Test Readwise connection") {
                        Task { await testReadwise() }
                    }
                    .disabled(state.readwiseKeyMasked.isEmpty || testing)
                    Button("Clear", role: .destructive) {
                        try? state.clearReadwiseKey()
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(statusIsError ? .red : .green)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var currentPreset: GeminiClient.ModelPreset? {
        GeminiClient.ModelPreset(rawValue: state.geminiModel)
    }

    private var modelSelection: Binding<GeminiClient.ModelPreset?> {
        Binding(
            get: { currentPreset },
            set: { newValue in
                if let preset = newValue {
                    state.geminiModel = preset.rawValue
                    customModelInput = ""
                } else {
                    customModelInput = state.geminiModel
                }
            }
        )
    }

    private func commitCustomModel() {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.geminiModel = trimmed
    }

    private enum Target { case gemini, readwise }

    private func save(_ keyPath: KeyPath<SettingsView, String>, target: Target) {
        do {
            switch target {
            case .gemini:
                try state.saveGeminiKey(geminiInput)
                geminiInput = ""
            case .readwise:
                try state.saveReadwiseKey(readwiseInput)
                readwiseInput = ""
            }
            setStatus("Saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func testGemini() async {
        guard let client = state.currentGeminiClient() else { return }
        testing = true
        defer { testing = false }
        // Minimal request: a 1×1 transparent PNG.
        let pixel = Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,
            0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,0x00,0x00,0x00,
            0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,
            0x45,0x4E,0x44,0xAE,0x42,0x60,0x82
        ])
        do {
            _ = try await client.extractHighlights(fromImages: [pixel], mimeType: "image/png")
            setStatus("Gemini key works.", isError: false)
        } catch GeminiError.invalidKey {
            setStatus("Gemini key rejected.", isError: true)
        } catch {
            setStatus("Gemini error: \(error.localizedDescription)", isError: true)
        }
    }

    private func testReadwise() async {
        guard let client = state.currentReadwiseClient() else { return }
        testing = true
        defer { testing = false }
        do {
            let ok = try await client.validateToken()
            setStatus(ok ? "Readwise token works." : "Readwise token rejected.", isError: !ok)
        } catch {
            setStatus("Readwise error: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
#endif
