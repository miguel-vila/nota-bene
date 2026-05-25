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
    @State private var addKeyFor: LLMProvider?

    private struct TestResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isError: Bool
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        providerSection
                        keySection
                        modelSection
                        readwiseSection
                        experimentalSection
                        debugSection
                        if let statusMessage {
                            Text(statusMessage)
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(statusIsError ? Theme.Palette.danger : Theme.Palette.success)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left")
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Theme.Typography.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .toolbarBackground(Theme.Palette.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert(item: $testResult) { result in
                Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(item: $addKeyFor) { provider in
                AddProviderKeyView(provider: provider) {
                    addKeyFor = nil
                }
                .environmentObject(state)
            }
        }
    }

    // MARK: Sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("PROVIDER")
            HStack(spacing: 0) {
                ForEach(LLMProvider.allCases) { provider in
                    Button {
                        selectProvider(provider)
                    } label: {
                        Text(provider.label)
                            .font(Theme.Typography.sans(14, weight: .medium))
                            .foregroundStyle(state.provider == provider ? Theme.Palette.bg : Theme.Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Layout.segmentedHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(state.provider == provider ? Theme.Palette.ink : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(Theme.Palette.line, lineWidth: 1)
            )
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("\(state.provider.label.uppercased()) · API KEY")
            ThemedCard {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Key",
                        trailing: AnyView(
                            Text(state.currentProviderKeyMasked.isEmpty ? "Not set" : state.currentProviderKeyMasked)
                                .font(Theme.Typography.mono(13))
                                .foregroundStyle(Theme.Palette.ink)
                        )
                    )
                    divider
                    settingsRow(
                        title: "Test connection",
                        trailing: AnyView(
                            Button {
                                Task { await testProvider() }
                            } label: {
                                Text(testing ? "Testing…" : "Test")
                                    .font(Theme.Typography.sans(13, weight: .medium))
                                    .foregroundStyle(state.currentProviderKeyMasked.isEmpty ? Theme.Palette.muted : Theme.Palette.inkSoft)
                            }
                            .disabled(state.currentProviderKeyMasked.isEmpty || testing)
                        )
                    )
                }
            }
            VStack(spacing: 8) {
                ThemedTextField("Replace key", text: $providerKeyInput, secure: true)
                HStack {
                    Button("Save \(state.provider.label) key") { saveProviderKey() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(providerKeyInput.isEmpty ? Theme.Palette.muted : Theme.Palette.ink)
                        .disabled(providerKeyInput.isEmpty)
                    Spacer()
                    Button("Clear") { clearProviderKey() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.danger)
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("\(state.provider.label.uppercased()) · MODEL")
            ThemedCard(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)) {
                VStack(spacing: 0) {
                    ForEach(Array(state.provider.presets.enumerated()), id: \.offset) { idx, preset in
                        modelRow(label: preset.label, value: preset.rawValue, hint: hint(for: preset.rawValue))
                        if idx < state.provider.presets.count - 1 || !isUsingPreset {
                            divider.padding(.horizontal, 10)
                        }
                    }
                    modelRow(label: "Custom…", value: nil, hint: isUsingPreset ? nil : state.currentModel)
                }
            }
            if !isUsingPreset {
                ThemedTextField("Model name", text: $customModelInput, monospaced: true)
                    .onSubmit { commitCustomModel() }
                Button("Use this model") { commitCustomModel() }
                    .font(Theme.Typography.sans(13, weight: .medium))
                    .foregroundStyle(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.Palette.muted : Theme.Palette.ink)
                    .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Text("Active")
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.muted)
                Spacer()
                Text(state.currentModel)
                    .font(Theme.Typography.mono(12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Button("Reset") { state.resetCurrentModelToDefault(); customModelInput = "" }
                    .font(Theme.Typography.sans(12, weight: .medium))
                    .foregroundStyle(state.currentModel == state.provider.defaultModel ? Theme.Palette.muted : Theme.Palette.inkSoft)
                    .disabled(state.currentModel == state.provider.defaultModel)
            }
            .padding(.horizontal, 4)
        }
    }

    private var readwiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("READWISE")
            ThemedCard {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Token",
                        trailing: AnyView(
                            Text(state.readwiseKeyMasked.isEmpty ? "Not set" : state.readwiseKeyMasked)
                                .font(Theme.Typography.mono(13))
                                .foregroundStyle(Theme.Palette.ink)
                        )
                    )
                    divider
                    settingsRow(
                        title: "Test connection",
                        trailing: AnyView(
                            Button {
                                Task { await testReadwise() }
                            } label: {
                                Text(testing ? "Testing…" : "Test")
                                    .font(Theme.Typography.sans(13, weight: .medium))
                                    .foregroundStyle(state.readwiseKeyMasked.isEmpty ? Theme.Palette.muted : Theme.Palette.inkSoft)
                            }
                            .disabled(state.readwiseKeyMasked.isEmpty || testing)
                        )
                    )
                }
            }
            VStack(spacing: 8) {
                ThemedTextField("Replace token", text: $readwiseInput, secure: true)
                HStack {
                    Button("Save Readwise key") { saveReadwise() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(readwiseInput.isEmpty ? Theme.Palette.muted : Theme.Palette.ink)
                        .disabled(readwiseInput.isEmpty)
                    Spacer()
                    Button("Clear") { try? state.clearReadwiseKey() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.danger)
                }
            }
        }
    }

    private var experimentalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("EXPERIMENTAL")
            ThemedCard {
                ToggleRow(
                    title: "Merge highlights",
                    subtitle: "Combine adjacent highlights in Review",
                    isOn: $state.experimentalMergeHighlights
                )
            }
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("DEBUG")
            ThemedCard {
                ToggleRow(
                    title: "Show response payload on errors",
                    subtitle: "Includes raw HTTP body in error messages",
                    isOn: $state.debugMode
                )
            }
        }
    }

    // MARK: Row helpers

    private func settingsRow(title: String, trailing: AnyView) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.sans(14))
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer()
            trailing
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.lineSoft).frame(height: 1)
    }

    private func modelRow(label: String, value: String?, hint: String?) -> some View {
        let isSelected: Bool = {
            if let value { return state.currentModel == value }
            return !isUsingPreset
        }()
        return Button {
            if let value {
                state.setCurrentModel(value)
                customModelInput = ""
            } else if isUsingPreset {
                customModelInput = state.currentModel
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.Typography.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    if let hint, !hint.isEmpty {
                        Text(hint)
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.muted)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isUsingPreset: Bool {
        state.provider.presets.contains(where: { $0.rawValue == state.currentModel })
    }

    private func hint(for raw: String) -> String? {
        if raw == state.provider.defaultModel { return "Recommended" }
        return nil
    }

    // MARK: Actions

    private func selectProvider(_ provider: LLMProvider) {
        guard state.provider != provider else { return }
        if hasKey(for: provider) {
            state.provider = provider
            providerKeyInput = ""
            customModelInput = ""
        } else {
            addKeyFor = provider
        }
    }

    private func hasKey(for provider: LLMProvider) -> Bool {
        switch provider {
        case .gemini: return !state.geminiKeyMasked.isEmpty
        case .claude: return !state.claudeKeyMasked.isEmpty
        }
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

// MARK: - Toggle row

private struct ToggleRow: View {
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
            BrandedToggle(isOn: $isOn)
        }
        .padding(.vertical, 4)
    }
}

private struct BrandedToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Palette.ink : Theme.Palette.line)
                    .frame(width: 44, height: 26)
                ZStack {
                    if isOn {
                        Circle()
                            .fill(Theme.Palette.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: -16)
                    }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .padding(.horizontal, 2)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add provider key (focused, single-step)

struct AddProviderKeyView: View {
    @EnvironmentObject private var state: AppState
    let provider: LLMProvider
    let onDone: () -> Void

    @State private var key: String = ""
    @State private var valid: Bool = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your \(provider.label) key.")
                            .font(Theme.Typography.serif(28))
                            .kerning(-0.6)
                            .lineSpacing(2)
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(.top, 8)

                        Text("Used only to read your highlighted pages with \(provider.label).")
                            .font(Theme.Typography.serif(15))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineSpacing(2)
                            .padding(.top, 10)

                        KeyField(
                            label: "\(provider.label) API key",
                            hint: providerHint,
                            hintURL: providerHintURL,
                            value: $key,
                            valid: valid
                        )
                        .padding(.top, 22)
                        .onChange(of: key) { _, _ in revalidate() }

                        PrivacyNotice()
                            .padding(.top, 16)

                        if let error {
                            Text(error)
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.danger)
                                .padding(.top, 12)
                        }

                        Button(action: save) {
                            Text("Save and switch to \(provider.label)")
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: valid))
                        .disabled(!valid)
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, Theme.Layout.setupPadding)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDone() }
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                ToolbarItem(placement: .principal) {
                    Text("Add \(provider.label) key")
                        .font(Theme.Typography.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .toolbarBackground(Theme.Palette.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { revalidate() }
    }

    private var providerHint: String {
        switch provider {
        case .gemini: return "aistudio.google.com → Get API key"
        case .claude: return "console.anthropic.com → API keys"
        }
    }

    private var providerHintURL: URL? {
        switch provider {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        }
    }

    private func revalidate() {
        valid = SetupValidation.looksLikeProviderKey(key, provider: provider)
    }

    private func save() {
        do {
            switch provider {
            case .gemini: try state.saveGeminiKey(key)
            case .claude: try state.saveClaudeKey(key)
            }
            state.provider = provider
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
