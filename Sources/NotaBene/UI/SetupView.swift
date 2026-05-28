#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var step: Step = .provider
    @State private var providerKey: String = ""
    @State private var readwiseKey: String = ""
    @State private var selectedTargets: Set<ExportTarget> = []
    @State private var targetQueue: [ExportTarget] = []
    @State private var finalizeError: String?

    enum Step: Equatable {
        case provider
        case providerKey
        case pickTargets
        case configureTarget(ExportTarget)
    }

    public init() {}

    public var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            switch step {
            case .provider:
                SetupProviderView(stepLabel: "Step 1 · Provider") {
                    step = .providerKey
                }
            case .providerKey:
                SetupProviderKeyView(
                    stepLabel: "Step 2 · API key",
                    providerKey: $providerKey
                ) {
                    step = .pickTargets
                }
            case .pickTargets:
                SetupPickTargetsView(
                    stepLabel: "Step 3 · Destinations",
                    selectedTargets: $selectedTargets
                ) {
                    let queue: [ExportTarget] = [.readwise, .notion]
                        .filter { selectedTargets.contains($0) }
                    targetQueue = queue
                    if let first = queue.first {
                        step = .configureTarget(first)
                    }
                }
            case .configureTarget(let target):
                SetupConfigureTargetView(
                    target: target,
                    stepLabel: stepLabel(for: target),
                    isLast: isLastTarget(target),
                    readwiseKey: $readwiseKey,
                    finalizeError: $finalizeError,
                    onComplete: { advance(from: target) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func stepLabel(for target: ExportTarget) -> String {
        let position = (targetQueue.firstIndex(of: target) ?? 0) + 4
        return "Step \(position) · \(target.label)"
    }

    private func isLastTarget(_ target: ExportTarget) -> Bool {
        targetQueue.last == target
    }

    private func advance(from target: ExportTarget) {
        guard let idx = targetQueue.firstIndex(of: target) else { return }
        let next = idx + 1
        if next < targetQueue.count {
            step = .configureTarget(targetQueue[next])
        } else {
            finalize()
        }
    }

    private func finalize() {
        do {
            try state.saveCurrentProviderKey(providerKey)
            if selectedTargets.contains(.readwise) {
                try state.saveReadwiseKey(readwiseKey)
            }
            for target in selectedTargets {
                state.enableTarget(target)
            }
            finalizeError = nil
        } catch {
            finalizeError = error.localizedDescription
        }
    }
}

// MARK: - Step 1: Provider

private struct SetupProviderView: View {
    @EnvironmentObject private var state: AppState
    let stepLabel: String
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(stepLabel)
                .padding(.top, 24)

            HeadlineWithSwipe(
                prefix: "Pick a vision model to read your ",
                accent: "highlights",
                suffix: ".",
                font: Theme.Typography.serif(38),
                lineSpacing: 4
            )
            .padding(.top, 18)

            Text("It will read your highlighted passages and turn them into highlights you can send to your chosen destinations.")
                .font(Theme.Typography.serif(16))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 14)
                .frame(maxWidth: 320, alignment: .leading)

            VStack(spacing: 14) {
                ForEach(LLMProvider.allCases) { provider in
                    ProviderCard(
                        provider: provider,
                        selected: state.provider == provider,
                        onSelect: { state.provider = provider }
                    )
                }
            }
            .padding(.top, 32)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
    }
}

private struct ProviderCard: View {
    let provider: LLMProvider
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                ProviderGlyph(provider: provider)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(provider.label)
                            .font(Theme.Typography.sans(16, weight: .semibold))
                            .kerning(-0.2)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(makerLabel)
                            .font(Theme.Typography.sans(12))
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    Text(description)
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                RadioDot(selected: selected)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(selected ? Theme.Palette.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(selected ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var makerLabel: String {
        switch provider {
        case .gemini: return "Google"
        case .claude: return "Anthropic"
        }
    }

    private var description: String {
        switch provider {
        case .gemini: return "Fast and cheap. Great default for most pages."
        case .claude: return "Reads tricky handwriting and faint marks well."
        }
    }
}

private struct ProviderGlyph: View {
    let provider: LLMProvider

    var body: some View {
        ZStack {
            switch provider {
            case .gemini:
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hex: 0x4285F4),
                                Color(hex: 0x9B72CB),
                                Color(hex: 0xD96570),
                                Color(hex: 0xF6AD55),
                                Color(hex: 0x4285F4)
                            ],
                            center: .center,
                            startAngle: .degrees(200),
                            endAngle: .degrees(560)
                        )
                    )
            case .claude:
                Circle().fill(Color(hex: 0xC96442))
                Text("a")
                    .font(.system(size: 18, weight: .regular, design: .serif).italic())
                    .foregroundStyle(.white)
                    .offset(y: -1)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct RadioDot: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle()
                .stroke(selected ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1.5)
            if selected {
                Circle().fill(Theme.Palette.ink).padding(2.5)
                Circle().fill(Theme.Palette.accent).frame(width: 8, height: 8)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct CheckboxDot: View {
    let selected: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if selected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Palette.ink)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
    }
}

// MARK: - Step 2: Provider key

private struct SetupProviderKeyView: View {
    @EnvironmentObject private var state: AppState
    let stepLabel: String
    @Binding var providerKey: String
    var onContinue: () -> Void
    @State private var valid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(stepLabel)
                .padding(.top, 24)

            Text("Your \(state.provider.label) key.")
                .font(Theme.Typography.serif(32))
                .kerning(-0.6)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            Text("Used only to read your highlighted pages with \(state.provider.label).")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 12)

            KeyField(
                label: "\(state.provider.label) API key",
                hint: providerHint,
                hintURL: providerHintURL,
                value: $providerKey,
                valid: valid
            )
            .padding(.top, 28)
            .onChange(of: providerKey) { _, _ in revalidate() }

            PrivacyNotice()
                .padding(.top, 18)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: valid))
            .disabled(!valid)
            .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
        .onAppear { revalidate() }
        .onChange(of: state.provider) { _, _ in
            providerKey = ""
            revalidate()
        }
    }

    private var providerHint: String {
        switch state.provider {
        case .gemini: return "aistudio.google.com → Get API key"
        case .claude: return "console.anthropic.com → API keys"
        }
    }

    private var providerHintURL: URL? {
        switch state.provider {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        }
    }

    private func revalidate() {
        valid = SetupValidation.looksLikeProviderKey(providerKey, provider: state.provider)
    }
}

// MARK: - Step 3: Pick targets

private struct SetupPickTargetsView: View {
    @EnvironmentObject private var state: AppState
    let stepLabel: String
    @Binding var selectedTargets: Set<ExportTarget>
    var onContinue: () -> Void

    private var notionAvailable: Bool {
        state.notionOAuthConfig != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(stepLabel)
                .padding(.top, 24)

            Text("Where should highlights go?")
                .font(Theme.Typography.serif(32))
                .kerning(-0.6)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            Text("Pick one or both. You can add or remove destinations later in Settings.")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 12)

            VStack(spacing: 14) {
                TargetCard(
                    target: .readwise,
                    selected: selectedTargets.contains(.readwise),
                    enabled: true,
                    disabledReason: nil
                ) {
                    toggle(.readwise)
                }
                TargetCard(
                    target: .notion,
                    selected: selectedTargets.contains(.notion),
                    enabled: notionAvailable,
                    disabledReason: notionAvailable
                        ? nil
                        : "Notion is unavailable in this build."
                ) {
                    if notionAvailable { toggle(.notion) }
                }
            }
            .padding(.top, 32)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !selectedTargets.isEmpty))
            .disabled(selectedTargets.isEmpty)
            .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
    }

    private func toggle(_ target: ExportTarget) {
        if selectedTargets.contains(target) {
            selectedTargets.remove(target)
        } else {
            selectedTargets.insert(target)
        }
    }
}

private struct TargetCard: View {
    let target: ExportTarget
    let selected: Bool
    let enabled: Bool
    let disabledReason: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                TargetGlyph(target: target)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.label)
                        .font(Theme.Typography.sans(16, weight: .semibold))
                        .kerning(-0.2)
                        .foregroundStyle(enabled ? Theme.Palette.ink : Theme.Palette.muted)
                    Text(disabledReason ?? target.shortDescription)
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                CheckboxDot(selected: selected)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(selected ? Theme.Palette.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(selected ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct TargetGlyph: View {
    let target: ExportTarget

    var body: some View {
        ZStack {
            switch target {
            case .readwise:
                Circle().fill(Color(hex: 0x2F6CFF))
                Text("R")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            case .notion:
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Theme.Palette.line, lineWidth: 1))
                Text("N")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Step 4: Configure a specific target

private struct SetupConfigureTargetView: View {
    let target: ExportTarget
    let stepLabel: String
    let isLast: Bool
    @Binding var readwiseKey: String
    @Binding var finalizeError: String?
    var onComplete: () -> Void

    var body: some View {
        switch target {
        case .readwise:
            SetupReadwiseStepView(
                stepLabel: stepLabel,
                isLast: isLast,
                readwiseKey: $readwiseKey,
                finalizeError: $finalizeError,
                onComplete: onComplete
            )
        case .notion:
            SetupNotionStepView(
                stepLabel: stepLabel,
                isLast: isLast,
                finalizeError: $finalizeError,
                onComplete: onComplete
            )
        }
    }
}

private struct SetupReadwiseStepView: View {
    let stepLabel: String
    let isLast: Bool
    @Binding var readwiseKey: String
    @Binding var finalizeError: String?
    var onComplete: () -> Void
    @State private var valid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(stepLabel)
                .padding(.top, 24)

            Text("Your Readwise token.")
                .font(Theme.Typography.serif(32))
                .kerning(-0.6)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            Text("Used only to send extracted highlights to your Readwise account.")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 12)

            KeyField(
                label: "Readwise token",
                hint: "readwise.io → Access Token",
                hintURL: URL(string: "https://readwise.io/access_token"),
                value: $readwiseKey,
                valid: valid
            )
            .padding(.top, 28)
            .onChange(of: readwiseKey) { _, _ in revalidate() }

            PrivacyNotice()
                .padding(.top, 18)

            if let err = finalizeError {
                Text(err)
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.danger)
                    .padding(.top, 12)
            }

            Spacer()

            Button(action: onComplete) {
                Text(isLast ? "Finish setup" : "Continue")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: valid))
            .disabled(!valid)

            Text("You can change keys later in Settings.")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
        .onAppear { revalidate() }
    }

    private func revalidate() {
        valid = SetupValidation.looksLikeReadwiseToken(readwiseKey)
    }
}

private struct SetupNotionStepView: View {
    @EnvironmentObject private var state: AppState
    let stepLabel: String
    let isLast: Bool
    @Binding var finalizeError: String?
    var onComplete: () -> Void

    @State private var pages: [NotionClient.PageReference] = []
    @State private var selectedPageID: String?
    @State private var isWorking: Bool = false
    @State private var stepError: String?

    private var connection: NotionConnection? { state.notionConnection }
    private var hasConnection: Bool { connection != nil }
    private var selectedPage: NotionClient.PageReference? {
        guard let id = selectedPageID else { return nil }
        return pages.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(stepLabel)
                .padding(.top, 24)

            Text("Connect Notion.")
                .font(Theme.Typography.serif(32))
                .kerning(-0.6)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            Text(hasConnection
                 ? "Pick the page where Nota Bene will create a sub-page per book."
                 : "Sign in once so highlights can be appended to a page in your workspace.")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 12)

            if let connection {
                connectedCard(connection)
                    .padding(.top, 24)

                pagePicker
                    .padding(.top, 18)
            } else {
                connectCard
                    .padding(.top, 28)
            }

            if let err = stepError ?? finalizeError {
                Text(err)
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.danger)
                    .padding(.top, 12)
            }

            Spacer()

            primaryButton

            Text("You can disconnect or change the parent page later in Settings.")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
        .onAppear { handleAppear() }
    }

    @ViewBuilder
    private var connectCard: some View {
        ThemedCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notion will ask which workspace and pages to grant access to. We only store the access token — no passwords.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Button(action: { Task { await connect() } }) {
                    HStack {
                        if isWorking {
                            ProgressView().tint(Theme.Palette.bg)
                        }
                        Text(isWorking ? "Connecting…" : "Connect Notion")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: Theme.Layout.secondaryButtonHeight, enabled: !isWorking))
                .disabled(isWorking)
            }
        }
    }

    @ViewBuilder
    private func connectedCard(_ connection: NotionConnection) -> some View {
        ThemedCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.Palette.surface)
                    .overlay(Circle().stroke(Theme.Palette.line, lineWidth: 1))
                    .overlay(
                        Text("N")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.Palette.ink)
                    )
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.workspaceName ?? "Notion workspace")
                        .font(Theme.Typography.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Connected")
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.success)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var pagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Parent page")
                    .font(Theme.Typography.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button(action: { Task { await loadPages() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh")
                            .font(Theme.Typography.sans(11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.inkSoft)
                }
                .disabled(isWorking)
            }

            if isWorking && pages.isEmpty {
                ThemedCard {
                    HStack {
                        ProgressView().tint(Theme.Palette.ink)
                        Text("Loading pages…")
                            .font(Theme.Typography.sans(13))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if pages.isEmpty {
                ThemedCard {
                    Text("No pages found. Share a page with Nota Bene from Notion's “Connections” menu, then refresh.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(pages, id: \.id) { page in
                        Button(action: { selectedPageID = page.id }) {
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
                                RadioDot(selected: selectedPageID == page.id)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                                    .fill(selectedPageID == page.id ? Theme.Palette.surface : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                                    .stroke(selectedPageID == page.id ? Theme.Palette.ink : Theme.Palette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let enabled: Bool = {
            guard hasConnection else { return false }
            return selectedPageID != nil && !isWorking
        }()
        Button(action: confirmAndAdvance) {
            Text(isLast ? "Finish setup" : "Continue")
        }
        .buttonStyle(PrimaryButtonStyle(enabled: enabled))
        .disabled(!enabled)
    }

    private func handleAppear() {
        if let conn = connection {
            if let parentID = conn.parentPageID, !parentID.isEmpty {
                selectedPageID = parentID
            }
            if pages.isEmpty {
                Task { await loadPages() }
            }
        }
    }

    private func connect() async {
        guard let oauth = state.currentNotionOAuth(),
              let scheme = state.notionOAuthConfig?.appRedirectScheme else {
            stepError = "Notion isn't configured for this build."
            return
        }
        isWorking = true
        stepError = nil
        defer { isWorking = false }
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
            await loadPages()
        } catch NotionOAuthError.userCancelled {
            // silent: user dismissed the sheet
        } catch {
            stepError = "Couldn't connect to Notion: \(error.localizedDescription)"
        }
    }

    private func loadPages() async {
        guard let client = state.currentNotionClient() else {
            stepError = "Notion client unavailable."
            return
        }
        isWorking = true
        stepError = nil
        defer { isWorking = false }
        do {
            let fetched = try await client.searchTopLevelPages()
            pages = fetched
            if let id = selectedPageID, !fetched.contains(where: { $0.id == id }) {
                selectedPageID = nil
            }
        } catch {
            stepError = "Couldn't load pages: \(error.localizedDescription)"
        }
    }

    private func confirmAndAdvance() {
        guard let page = selectedPage else { return }
        state.updateNotionParentPage(pageID: page.id, title: page.title)
        finalizeError = nil
        onComplete()
    }
}

// MARK: - KeyField

struct KeyField: View {
    let label: String
    let hint: String
    var hintURL: URL? = nil
    @Binding var value: String
    let valid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.Typography.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let hintURL {
                    Link(destination: hintURL) {
                        HStack(spacing: 4) {
                            Text(hint)
                                .font(Theme.Typography.mono(10))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(Theme.Palette.inkSoft)
                    }
                } else {
                    Text(hint)
                        .font(Theme.Typography.mono(10))
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            HStack(spacing: 10) {
                SecureField("Paste token", text: $value)
                    .font(Theme.Typography.mono(13))
                    .foregroundStyle(Theme.Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if valid {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Valid")
                            .font(Theme.Typography.sans(11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.success)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                    .stroke(Theme.Palette.line, lineWidth: 1)
            )
        }
    }
}

// MARK: - Privacy notice

struct PrivacyNotice: View {
    private let repoURL = URL(string: "https://github.com/miguel-vila/nota-bene")!

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your keys never leave this device. We don't store or send them anywhere — they live only in your iOS Keychain and are used only to call the service they're for.")
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: repoURL) {
                    HStack(spacing: 4) {
                        Text("Source: github.com/miguel-vila/nota-bene")
                            .font(Theme.Typography.mono(11))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.ink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }
}

// MARK: - Headline with swipe

struct HeadlineWithSwipe: View {
    let prefix: String
    let accent: String
    let suffix: String
    let font: Font
    var lineSpacing: CGFloat = 0
    var swipeColor: Color = Theme.Palette.accent

    var body: some View {
        let parts: AttributedString = {
            var prefixStr = AttributedString(prefix)
            prefixStr.foregroundColor = Theme.Palette.ink

            var accentStr = AttributedString(accent)
            accentStr.foregroundColor = Theme.Palette.ink
            accentStr.backgroundColor = swipeColor

            var suffixStr = AttributedString(suffix)
            suffixStr.foregroundColor = Theme.Palette.ink

            return prefixStr + accentStr + suffixStr
        }()

        Text(parts)
            .font(font)
            .lineSpacing(lineSpacing)
            .kerning(-0.6)
            .foregroundStyle(Theme.Palette.ink)
    }
}

// MARK: - Validation helpers

enum SetupValidation {
    static func looksLikeProviderKey(_ key: String, provider: LLMProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch provider {
        case .gemini:
            return trimmed.hasPrefix("AIza") && trimmed.count >= 35
        case .claude:
            return trimmed.hasPrefix("sk-ant-") && trimmed.count >= 30
        }
    }

    static func looksLikeReadwiseToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 20 && trimmed.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
#endif
