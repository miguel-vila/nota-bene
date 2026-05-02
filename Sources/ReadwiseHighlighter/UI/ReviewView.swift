#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
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
                    if state.experimentalMergeHighlights,
                       let index = indexFor(highlight),
                       index > 0 {
                        Button {
                            flow.mergeHighlight(at: index)
                        } label: {
                            Label("Merge with above", systemImage: "arrow.up")
                        }
                        .disabled(flow.stage == .submitting)
                    }
                    TextEditor(text: $highlight.text)
                        .frame(minHeight: 120)
                    TextField("Page number (optional)", text: $highlight.pageNumberInput)
                        .keyboardType(.numberPad)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $highlight.note)
                            .frame(minHeight: 60)
                    }
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
              let index = indexFor(highlight) else {
            return "Highlight"
        }
        return "Highlight \(index + 1)"
    }

    private func indexFor(_ highlight: CaptureFlow.EditableHighlight) -> Int? {
        flow.highlights.firstIndex(where: { $0.id == highlight.id })
    }

    private var saveButtonTitle: String {
        let count = flow.savableHighlights.count
        if count <= 1 { return "Save to Readwise" }
        return "Save \(count) highlights to Readwise"
    }
}
#endif
