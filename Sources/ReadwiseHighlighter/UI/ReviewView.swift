#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct ReviewView: View {
    @ObservedObject var flow: CaptureFlow
    var onSave: () async -> Void
    var onCancel: () -> Void

    var body: some View {
        Form {
            Section("Book") {
                VStack(alignment: .leading) {
                    Text(flow.book.title).font(.body)
                    if let author = flow.book.author, !author.isEmpty {
                        Text(author).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if flow.didDetectEmptyHighlight {
                Section {
                    Text("No highlight detected — type the passage manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Highlight") {
                TextEditor(text: $flow.extractedText)
                    .frame(minHeight: 140)
            }

            Section("Page number") {
                TextField("Optional", text: $flow.pageNumberInput)
                    .keyboardType(.numberPad)
            }

            if let error = flow.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await onSave() }
                } label: {
                    if flow.stage == .submitting {
                        ProgressView()
                    } else {
                        Text("Save to Readwise")
                    }
                }
                .disabled(!flow.canSave || flow.stage == .submitting)

                Button(role: .destructive, action: onCancel) {
                    Text("Cancel")
                }
                .disabled(flow.stage == .submitting)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
