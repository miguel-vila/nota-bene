#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var geminiKey = ""
    @State private var readwiseKey = ""
    @State private var error: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paste your API keys to get started. They are stored in the iOS Keychain on this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Gemini API key") {
                    SecureField("AIza...", text: $geminiKey)
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
                        .disabled(geminiKey.isEmpty || readwiseKey.isEmpty)
                }
            }
            .navigationTitle("Setup")
        }
    }

    private func save() {
        do {
            try state.saveGeminiKey(geminiKey)
            try state.saveReadwiseKey(readwiseKey)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
