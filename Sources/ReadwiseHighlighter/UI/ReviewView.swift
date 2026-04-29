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

            ForEach($flow.highlights) { $highlight in
                Section {
                    TextEditor(text: $highlight.text)
                        .frame(minHeight: 120)
                    TextField("Page number (optional)", text: $highlight.pageNumberInput)
                        .keyboardType(.numberPad)
                    if flow.highlights.count > 1 {
                        Button(role: .destructive) {
                            flow.removeHighlight(id: highlight.id)
                        } label: {
                            Label("Remove highlight", systemImage: "trash")
                        }
                    }
                } header: {
                    Text(headerTitle(for: highlight))
                }
            }

            Section {
                Button {
                    flow.addBlankHighlight()
                } label: {
                    Label("Add another highlight", systemImage: "plus.circle")
                }
                .disabled(flow.stage == .submitting)
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
                        Text(saveButtonTitle)
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

    private func headerTitle(for highlight: CaptureFlow.EditableHighlight) -> String {
        guard flow.highlights.count > 1,
              let index = flow.highlights.firstIndex(where: { $0.id == highlight.id }) else {
            return "Highlight"
        }
        return "Highlight \(index + 1)"
    }

    private var saveButtonTitle: String {
        let count = flow.savableHighlights.count
        if count <= 1 { return "Save to Readwise" }
        return "Save \(count) highlights to Readwise"
    }
}
#endif
