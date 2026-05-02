#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var providerKeyInput = ""
    @State private var readwiseInput = ""
    @State private var customModelInput = ""
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var testing: Bool = false
    @State private var testResult: TestResult?

    private struct TestResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isError: Bool
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Model provider") {
                    Picker("Provider", selection: $state.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .onChange(of: state.provider) { _, _ in
                        providerKeyInput = ""
                        customModelInput = ""
                    }
                }

                Section("\(state.provider.label) API key") {
                    HStack {
                        Text("Stored").foregroundStyle(.secondary)
                        Spacer()
                        Text(state.currentProviderKeyMasked.isEmpty ? "Not set" : state.currentProviderKeyMasked)
                            .font(.system(.body, design: .monospaced))
                    }
                    SecureField("Replace key", text: $providerKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save \(state.provider.label) key") {
                        saveProviderKey()
                    }
                    .disabled(providerKeyInput.isEmpty)
                    Button("Test \(state.provider.label) connection") {
                        Task { await testProvider() }
                    }
                    .disabled(state.currentProviderKeyMasked.isEmpty || testing)
                    Button("Clear", role: .destructive) {
                        clearProviderKey()
                    }
                }

                Section("\(state.provider.label) model") {
                    Picker("Model", selection: modelSelection) {
                        ForEach(state.provider.presets) { preset in
                            Text(preset.label).tag(Optional(preset.rawValue))
                        }
                        Text("Custom…").tag(Optional<String>.none)
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
                        Text(state.currentModel)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button("Reset to default") {
                        state.resetCurrentModelToDefault()
                        customModelInput = ""
                    }
                    .disabled(state.currentModel == state.provider.defaultModel)
                }

                Section("Debug") {
                    Toggle("Show response payload on errors", isOn: $state.debugMode)
                    if state.debugMode {
                        Text("Non-2xx responses from the model and Readwise APIs will include the raw body in the error message. Useful when an extraction or test fails for an unclear reason.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                        saveReadwise()
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
            .alert(item: $testResult) { result in
                Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var currentPreset: String? {
        let active = state.currentModel
        return state.provider.presets.first(where: { $0.rawValue == active })?.rawValue
    }

    private var modelSelection: Binding<String?> {
        Binding(
            get: { currentPreset },
            set: { newValue in
                if let raw = newValue {
                    state.setCurrentModel(raw)
                    customModelInput = ""
                } else {
                    customModelInput = state.currentModel
                }
            }
        )
    }

    private func commitCustomModel() {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.setCurrentModel(trimmed)
    }

    private func saveProviderKey() {
        do {
            try state.saveCurrentProviderKey(providerKeyInput)
            providerKeyInput = ""
            setStatus("Saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveReadwise() {
        do {
            try state.saveReadwiseKey(readwiseInput)
            readwiseInput = ""
            setStatus("Saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func clearProviderKey() {
        do {
            switch state.provider {
            case .gemini: try state.clearGeminiKey()
            case .claude: try state.clearClaudeKey()
            }
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func testProvider() async {
        guard let extractor = state.currentExtractor() else { return }
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
        let label = state.provider.label
        do {
            _ = try await extractor.extractHighlights(fromImages: [pixel], mimeType: "image/png")
            showTestResult(title: "Connection succeeded", message: "\(label) key works.", isError: false)
        } catch ExtractionError.invalidKey {
            showTestResult(title: "Connection failed", message: "\(label) key rejected.", isError: true)
        } catch ExtractionError.requestFailed(let status, let body) {
            let detail = state.debugMode ? "\n\n\(body.isEmpty ? "(empty body)" : body)" : ""
            showTestResult(
                title: "Connection failed",
                message: "\(label) returned HTTP \(status).\(detail)",
                isError: true
            )
        } catch ExtractionError.missingContent(let payload) {
            let detail = state.debugMode ? "\n\nResponse:\n\(payload.isEmpty ? "(empty)" : payload)" : ""
            showTestResult(
                title: "Connection failed",
                message: "\(label) response had no extractable content.\(detail)",
                isError: true
            )
        } catch ExtractionError.decoding(let reason, let payload) {
            let detail = state.debugMode ? "\n\nResponse:\n\(payload.isEmpty ? "(empty)" : payload)" : ""
            showTestResult(
                title: "Connection failed",
                message: "Couldn't parse \(label) response: \(reason).\(detail)",
                isError: true
            )
        } catch {
            showTestResult(title: "Connection failed", message: "\(label) error: \(error.localizedDescription)", isError: true)
        }
    }

    private func testReadwise() async {
        guard let client = state.currentReadwiseClient() else { return }
        testing = true
        defer { testing = false }
        do {
            let ok = try await client.validateToken()
            showTestResult(
                title: ok ? "Connection succeeded" : "Connection failed",
                message: ok ? "Readwise token works." : "Readwise token rejected.",
                isError: !ok
            )
        } catch ReadwiseError.requestFailed(let status, let body) {
            let detail = state.debugMode ? "\n\n\(body.isEmpty ? "(empty body)" : body)" : ""
            showTestResult(
                title: "Connection failed",
                message: "Readwise returned HTTP \(status).\(detail)",
                isError: true
            )
        } catch {
            showTestResult(title: "Connection failed", message: "Readwise error: \(error.localizedDescription)", isError: true)
        }
    }

    private func showTestResult(title: String, message: String, isError: Bool) {
        testResult = TestResult(title: title, message: message, isError: isError)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
#endif
