#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var step: Step = .provider

    enum Step { case provider, keys }

    public init() {}

    public var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            switch step {
            case .provider:
                SetupProviderView { step = .keys }
            case .keys:
                SetupKeysView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }
}

// MARK: - Step 1: Provider

private struct SetupProviderView: View {
    @EnvironmentObject private var state: AppState
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Step 1 of 3 · Setup")
                .padding(.top, 24)

            HeadlineWithSwipe(
                prefix: "Pick a vision model to read your ",
                accent: "highlights",
                suffix: ".",
                font: Theme.Typography.serif(38),
                lineSpacing: 4
            )
            .padding(.top, 18)

            Text("It will read your highlighted passages and turn them into Readwise highlights.")
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

// MARK: - Step 2: Keys

private struct SetupKeysView: View {
    @EnvironmentObject private var state: AppState
    @State private var providerKey: String = ""
    @State private var readwiseKey: String = ""
    @State private var providerValid: Bool = false
    @State private var readwiseValid: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Step 2 of 3 · Keys")
                .padding(.top, 24)

            Text("Two keys, then we're done.")
                .font(Theme.Typography.serif(32))
                .kerning(-0.6)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            Text("Stored in your iOS Keychain. Never sent anywhere except the service it's for.")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .padding(.top, 12)

            VStack(spacing: 14) {
                KeyField(
                    label: "\(state.provider.label) API key",
                    hint: providerHint,
                    value: $providerKey,
                    valid: providerValid
                )
                .onChange(of: providerKey) { _, _ in revalidateProvider() }

                KeyField(
                    label: "Readwise token",
                    hint: "readwise.io → Access Token",
                    value: $readwiseKey,
                    valid: readwiseValid
                )
                .onChange(of: readwiseKey) { _, _ in revalidateReadwise() }
            }
            .padding(.top, 28)

            if let error {
                Text(error)
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.danger)
                    .padding(.top, 12)
            }

            Spacer()

            Button(action: save) {
                Text("Finish setup")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canFinish))
            .disabled(!canFinish)

            Text("You can change keys later in Settings.")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 38)
        }
        .padding(.horizontal, Theme.Layout.setupPadding)
        .onAppear {
            revalidateProvider()
            revalidateReadwise()
        }
        .onChange(of: state.provider) { _, _ in
            providerKey = ""
            revalidateProvider()
        }
    }

    private var providerHint: String {
        switch state.provider {
        case .gemini: return "aistudio.google.com → Get API key"
        case .claude: return "console.anthropic.com → API keys"
        }
    }

    private var canFinish: Bool {
        providerValid && readwiseValid
    }

    private func revalidateProvider() {
        providerValid = SetupValidation.looksLikeProviderKey(providerKey, provider: state.provider)
    }

    private func revalidateReadwise() {
        readwiseValid = SetupValidation.looksLikeReadwiseToken(readwiseKey)
    }

    private func save() {
        do {
            try state.saveCurrentProviderKey(providerKey)
            try state.saveReadwiseKey(readwiseKey)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - KeyField

private struct KeyField: View {
    let label: String
    let hint: String
    @Binding var value: String
    let valid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.Typography.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(hint)
                    .font(Theme.Typography.mono(10))
                    .foregroundStyle(Theme.Palette.muted)
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
