#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var providerKey = ""
    @State private var readwiseKey = ""
    @State private var error: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pick a model provider, then paste your API keys to get started. They are stored in the iOS Keychain on this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Model provider") {
                    Picker("Provider", selection: $state.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .onChange(of: state.provider) { _, _ in providerKey = "" }
                }
                Section("\(state.provider.label) API key") {
                    SecureField(placeholder, text: $providerKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Readwise API key") {
                    SecureField("Token", text: $readwiseKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Save & continue") { save() }
                        .disabled(providerKey.isEmpty || readwiseKey.isEmpty)
                }
            }
            .navigationTitle("Setup")
        }
    }

    private var placeholder: String {
        switch state.provider {
        case .gemini: return "AIza..."
        case .claude: return "sk-ant-..."
        }
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
#endif
