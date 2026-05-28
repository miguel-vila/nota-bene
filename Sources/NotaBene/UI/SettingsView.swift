#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var customModelInput = ""
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var testingProvider: Bool = false
    @State private var testingReadwise: Bool = false
    @State private var testingNotion: Bool = false
    @State private var testResult: TestResult?
    @State private var addKeyFor: LLMProvider?
    @State private var showingReadwiseKeySheet: Bool = false
    @State private var toastMessage: String?
    @State private var notionWorking: Bool = false
    @State private var notionError: String?
    @State private var showingParentPagePicker: Bool = false

    private struct TestResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isError: Bool
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        modelGroup
                        exportTargetsGroup
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
                toastOverlay
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
            .sheet(isPresented: $showingReadwiseKeySheet) {
                AddReadwiseTokenView {
                    showingReadwiseKeySheet = false
                }
                .environmentObject(state)
            }
            .sheet(isPresented: $showingParentPagePicker) {
                NotionParentPagePickerView(
                    currentPageID: state.notionConnection?.parentPageID
                ) { picked in
                    if let picked {
                        state.updateNotionParentPage(pageID: picked.id, title: picked.title)
                    }
                    showingParentPagePicker = false
                }
                .environmentObject(state)
            }
        }
    }

    // MARK: - Model group

    private var modelGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel("MODEL")
            providerSection
            keySection
            modelSection
        }
    }

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
                    editableKeyRow(
                        title: "Key",
                        valueMasked: state.currentProviderKeyMasked,
                        emptyLabel: "Add key"
                    ) {
                        addKeyFor = state.provider
                    }
                    divider
                    settingsRow(
                        title: "Test connection",
                        trailing: AnyView(
                            Button {
                                Task { await testProvider() }
                            } label: {
                                Text(testingProvider ? "Testing…" : "Test")
                                    .font(Theme.Typography.sans(13, weight: .medium))
                                    .foregroundStyle(state.currentProviderKeyMasked.isEmpty ? Theme.Palette.muted : Theme.Palette.inkSoft)
                            }
                            .disabled(state.currentProviderKeyMasked.isEmpty || testingProvider)
                        )
                    )
                }
            }
            if !state.currentProviderKeyMasked.isEmpty {
                HStack {
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

    // MARK: - Export targets group

    private var exportTargetsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("EXPORT TARGETS")
            Text("Each save fans out to every destination that's enabled and configured.")
                .font(Theme.Typography.sans(12))
                .foregroundStyle(Theme.Palette.muted)

            readwiseTargetCard
            if shouldShowNotion {
                notionTargetCard
            }
        }
    }

    private var shouldShowNotion: Bool {
        state.notionOAuthConfig != nil || state.notionConnection != nil
    }

    private var readwiseTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TargetHeader(
                target: .readwise,
                isOn: targetBinding(for: .readwise),
                disabledReason: state.isTargetConfigured(.readwise) ? nil : "Add your token to enable"
            )
            ThemedCard {
                VStack(spacing: 0) {
                    editableKeyRow(
                        title: "Token",
                        valueMasked: state.readwiseKeyMasked,
                        emptyLabel: "Add token"
                    ) {
                        showingReadwiseKeySheet = true
                    }
                    if state.isTargetConfigured(.readwise) {
                        divider
                        settingsRow(
                            title: "Test connection",
                            trailing: AnyView(
                                Button {
                                    Task { await testReadwise() }
                                } label: {
                                    Text(testingReadwise ? "Testing…" : "Test")
                                        .font(Theme.Typography.sans(13, weight: .medium))
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                }
                                .disabled(testingReadwise)
                            )
                        )
                    }
                }
            }
            if state.isTargetConfigured(.readwise) {
                HStack {
                    Spacer()
                    Button("Clear") { clearReadwise() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.danger)
                }
            }
        }
    }

    private var notionTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TargetHeader(
                target: .notion,
                isOn: targetBinding(for: .notion),
                disabledReason: state.isTargetConfigured(.notion) ? nil : notionMissingReason
            )

            if let connection = state.notionConnection {
                ThemedCard {
                    VStack(spacing: 0) {
                        settingsRow(
                            title: "Workspace",
                            trailing: AnyView(
                                Text(connection.workspaceName ?? "Connected")
                                    .font(Theme.Typography.sans(13))
                                    .foregroundStyle(Theme.Palette.ink)
                            )
                        )
                        divider
                        Button { showingParentPagePicker = true } label: {
                            HStack {
                                Text("Parent page")
                                    .font(Theme.Typography.sans(14))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                Spacer()
                                Text(connection.parentPageTitle ?? "Choose…")
                                    .font(Theme.Typography.sans(13))
                                    .foregroundStyle(connection.parentPageID == nil ? Theme.Palette.danger : Theme.Palette.ink)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.muted)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if state.isTargetConfigured(.notion) {
                            divider
                            settingsRow(
                                title: "Test connection",
                                trailing: AnyView(
                                    Button {
                                        Task { await testNotion() }
                                    } label: {
                                        Text(testingNotion ? "Testing…" : "Test")
                                            .font(Theme.Typography.sans(13, weight: .medium))
                                            .foregroundStyle(Theme.Palette.inkSoft)
                                    }
                                    .disabled(testingNotion)
                                )
                            )
                        }
                    }
                }
                HStack {
                    Button(notionWorking ? "Working…" : "Reconnect") {
                        Task { await reconnectNotion() }
                    }
                    .font(Theme.Typography.sans(13, weight: .medium))
                    .foregroundStyle(notionWorking || state.notionOAuthConfig == nil ? Theme.Palette.muted : Theme.Palette.ink)
                    .disabled(notionWorking || state.notionOAuthConfig == nil)
                    Spacer()
                    Button("Disconnect") { disconnectNotion() }
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.danger)
                }
            } else {
                ThemedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sign in once so highlights can be appended to a page in your workspace.")
                            .font(Theme.Typography.sans(13))
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Button(action: { Task { await connectNotion() } }) {
                            HStack {
                                if notionWorking {
                                    ProgressView().tint(Theme.Palette.bg)
                                }
                                Text(notionWorking ? "Connecting…" : "Connect Notion")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(height: Theme.Layout.secondaryButtonHeight, enabled: !notionWorking))
                        .disabled(notionWorking || state.notionOAuthConfig == nil)
                    }
                }
            }

            if let notionError {
                Text(notionError)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
    }

    private var notionMissingReason: String {
        if state.notionConnection == nil { return "Connect to enable" }
        if state.notionConnection?.parentPageID == nil { return "Pick a parent page to enable" }
        return "Not configured"
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

    // MARK: - Toast overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(Theme.Typography.sans(13, weight: .medium))
                .foregroundStyle(Theme.Palette.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.Palette.ink)
                )
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.25)) {
                                self.toastMessage = nil
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Row helpers

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

    private func editableKeyRow(
        title: String,
        valueMasked: String,
        emptyLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer()
                Text(valueMasked.isEmpty ? emptyLabel : valueMasked)
                    .font(valueMasked.isEmpty ? Theme.Typography.sans(13, weight: .medium) : Theme.Typography.mono(13))
                    .foregroundStyle(valueMasked.isEmpty ? Theme.Palette.inkSoft : Theme.Palette.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.muted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - Actions

    private func targetBinding(for target: ExportTarget) -> Binding<Bool> {
        Binding(
            get: {
                state.enabledTargets.contains(target) && state.isTargetConfigured(target)
            },
            set: { newValue in
                if newValue {
                    if state.isTargetConfigured(target) {
                        state.enableTarget(target)
                    } else {
                        showToast("Configure \(target.label) before enabling it.")
                    }
                } else {
                    do {
                        try state.disableTarget(target)
                    } catch {
                        showToast("At least one destination must stay on.")
                    }
                }
            }
        )
    }

    private func selectProvider(_ provider: LLMProvider) {
        guard state.provider != provider else { return }
        if hasKey(for: provider) {
            state.provider = provider
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

    private func clearReadwise() {
        do {
            try state.clearReadwiseKey()
            setStatus("Readwise token cleared.", isError: false)
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

    private func connectNotion() async {
        guard let oauth = state.currentNotionOAuth(),
              let scheme = state.notionOAuthConfig?.appRedirectScheme else {
            notionError = "Notion isn't configured for this build."
            return
        }
        notionWorking = true
        notionError = nil
        defer { notionWorking = false }
        do {
            let session = NotionOAuthSession(oauth: oauth, appRedirectScheme: scheme)
            let token = try await session.connect()
            let conn = NotionConnection(
                workspaceID: token.workspaceID,
                workspaceName: token.workspaceName,
                workspaceIcon: token.workspaceIcon.flatMap { URL(string: $0) },
                botID: token.botID
            )
            try state.saveNotionConnection(conn, accessToken: token.accessToken)
            showingParentPagePicker = true
        } catch NotionOAuthError.userCancelled {
            // silent
        } catch {
            notionError = "Couldn't connect: \(error.localizedDescription)"
        }
    }

    private func reconnectNotion() async {
        guard let oauth = state.currentNotionOAuth(),
              let scheme = state.notionOAuthConfig?.appRedirectScheme else {
            notionError = "Notion isn't configured for this build."
            return
        }
        notionWorking = true
        notionError = nil
        defer { notionWorking = false }
        do {
            let session = NotionOAuthSession(oauth: oauth, appRedirectScheme: scheme)
            let token = try await session.connect()
            let existing = state.notionConnection
            let conn = NotionConnection(
                workspaceID: token.workspaceID,
                workspaceName: token.workspaceName,
                workspaceIcon: token.workspaceIcon.flatMap { URL(string: $0) },
                botID: token.botID,
                parentPageID: existing?.parentPageID,
                parentPageTitle: existing?.parentPageTitle,
                bookPageCache: existing?.bookPageCache ?? [:],
                connectedAt: Date()
            )
            try state.saveNotionConnection(conn, accessToken: token.accessToken)
            setStatus("Notion reconnected.", isError: false)
        } catch NotionOAuthError.userCancelled {
            // silent
        } catch {
            notionError = "Couldn't reconnect: \(error.localizedDescription)"
        }
    }

    private func disconnectNotion() {
        do {
            try state.clearNotionConnection()
            notionError = nil
            setStatus("Notion disconnected.", isError: false)
        } catch {
            notionError = error.localizedDescription
        }
    }

    private func testProvider() async {
        guard let extractor = state.currentExtractor() else { return }
        testingProvider = true
        defer { testingProvider = false }
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
        testingReadwise = true
        defer { testingReadwise = false }
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

    private func testNotion() async {
        guard let client = state.currentNotionClient() else { return }
        testingNotion = true
        defer { testingNotion = false }
        do {
            let ok = try await client.validateToken()
            showTestResult(
                title: ok ? "Connection succeeded" : "Connection failed",
                message: ok ? "Notion token works." : "Notion token rejected.",
                isError: !ok
            )
        } catch NotionError.requestFailed(let status, let body) {
            let detail = state.debugMode ? "\n\n\(body.isEmpty ? "(empty body)" : body)" : ""
            showTestResult(
                title: "Connection failed",
                message: "Notion returned HTTP \(status).\(detail)",
                isError: true
            )
        } catch {
            showTestResult(title: "Connection failed", message: "Notion error: \(error.localizedDescription)", isError: true)
        }
    }

    private func showTestResult(title: String, message: String, isError: Bool) {
        testResult = TestResult(title: title, message: message, isError: isError)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = message
        }
    }
}

// MARK: - Target header

private struct TargetHeader: View {
    let target: ExportTarget
    @Binding var isOn: Bool
    let disabledReason: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            targetGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(target.label)
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(disabledReason ?? "On — saving will send highlights here")
                    .font(Theme.Typography.sans(11))
                    .foregroundStyle(disabledReason != nil ? Theme.Palette.muted : Theme.Palette.inkSoft)
            }
            Spacer()
            BrandedToggle(isOn: $isOn)
        }
        .padding(.horizontal, 4)
    }

    private var targetGlyph: some View {
        ZStack {
            switch target {
            case .readwise:
                Circle().fill(Color(hex: 0x2F6CFF))
                Text("R")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            case .notion:
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Theme.Palette.line, lineWidth: 1))
                Text("N")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Notion parent page picker

private struct NotionParentPagePickerView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let currentPageID: String?
    var onPick: (NotionClient.PageReference?) -> Void

    @State private var pages: [NotionClient.PageReference] = []
    @State private var loading: Bool = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                if loading && pages.isEmpty {
                    ProgressView().tint(Theme.Palette.ink)
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(Theme.Typography.sans(14))
                            .foregroundStyle(Theme.Palette.danger)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(pages, id: \.id) { page in
                                Button {
                                    onPick(page)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Theme.Palette.inkSoft)
                                            .frame(width: 22)
                                        Text(page.title)
                                            .font(Theme.Typography.sans(14))
                                            .foregroundStyle(Theme.Palette.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        if page.id == currentPageID {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Theme.Palette.ink)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                                            .fill(page.id == currentPageID ? Theme.Palette.surface : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                                            .stroke(page.id == currentPageID ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            if pages.isEmpty && !loading {
                                Text("No pages found. Share a page with Nota Bene from Notion's “Connections” menu, then refresh.")
                                    .font(Theme.Typography.sans(13))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .multilineTextAlignment(.center)
                                    .padding(24)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onPick(nil) }
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                ToolbarItem(placement: .principal) {
                    Text("Parent page")
                        .font(Theme.Typography.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .disabled(loading)
                }
            }
            .toolbarBackground(Theme.Palette.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { Task { await load() } }
    }

    private func load() async {
        guard let client = state.currentNotionClient() else {
            error = "Notion client unavailable."
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            pages = try await client.searchTopLevelPages()
        } catch {
            self.error = error.localizedDescription
        }
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

    private var isReplacing: Bool {
        switch provider {
        case .gemini: return !state.geminiKeyMasked.isEmpty
        case .claude: return !state.claudeKeyMasked.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isReplacing ? "Replace your \(provider.label) key." : "Your \(provider.label) key.")
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
                            Text(isReplacing ? "Replace \(provider.label) key" : "Save \(provider.label) key")
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
                    Text(isReplacing ? "Replace \(provider.label) key" : "Add \(provider.label) key")
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

// MARK: - Add Readwise token (focused, single-step)

struct AddReadwiseTokenView: View {
    @EnvironmentObject private var state: AppState
    let onDone: () -> Void

    @State private var token: String = ""
    @State private var valid: Bool = false
    @State private var error: String?

    private var isReplacing: Bool {
        !state.readwiseKeyMasked.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isReplacing ? "Replace your Readwise token." : "Your Readwise token.")
                            .font(Theme.Typography.serif(28))
                            .kerning(-0.6)
                            .lineSpacing(2)
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(.top, 8)

                        Text("Used only to send extracted highlights to your Readwise account.")
                            .font(Theme.Typography.serif(15))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineSpacing(2)
                            .padding(.top, 10)

                        KeyField(
                            label: "Readwise token",
                            hint: "readwise.io → Access Token",
                            hintURL: URL(string: "https://readwise.io/access_token"),
                            value: $token,
                            valid: valid
                        )
                        .padding(.top, 22)
                        .onChange(of: token) { _, _ in revalidate() }

                        PrivacyNotice()
                            .padding(.top, 16)

                        if let error {
                            Text(error)
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.danger)
                                .padding(.top, 12)
                        }

                        Button(action: save) {
                            Text(isReplacing ? "Replace Readwise token" : "Save Readwise token")
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
                    Text(isReplacing ? "Replace Readwise token" : "Add Readwise token")
                        .font(Theme.Typography.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .toolbarBackground(Theme.Palette.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { revalidate() }
    }

    private func revalidate() {
        valid = SetupValidation.looksLikeReadwiseToken(token)
    }

    private func save() {
        do {
            try state.saveReadwiseKey(token)
            if !state.enabledTargets.contains(.readwise) {
                state.enableTarget(.readwise)
            }
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
