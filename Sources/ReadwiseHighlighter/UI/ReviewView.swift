#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var flow: CaptureFlow
    var onSave: () async -> Void
    var onCancel: () -> Void
    var onChangeBook: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        bookStrip
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        if flow.didDetectEmptyHighlight {
                            Text("No highlight detected — type the passage manually.")
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.muted)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)
                        }

                        highlightsHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        VStack(spacing: 10) {
                            ForEach(Array($flow.highlights.enumerated()), id: \.element.id) { index, $highlight in
                                HighlightCard(
                                    flow: flow,
                                    highlight: $highlight,
                                    index: index,
                                    showMerge: state.experimentalMergeHighlights && index > 0,
                                    canRemove: flow.highlights.count > 1
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                        if let error = flow.lastError {
                            Text(error)
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.danger)
                                .padding(.horizontal, 24)
                                .padding(.top, 14)
                        }

                        Spacer().frame(height: 120)
                    }
                }
            }

            saveBar
        }
        .navigationBarHidden(true)
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text("Review")
                .font(Theme.Typography.sans(15, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { onCancel() } label: {
                Text("Cancel")
                    .font(Theme.Typography.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted)
                    .frame(width: 60, height: 40, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var bookStrip: some View {
        HStack(spacing: 12) {
            CoverThumbnail(title: flow.book.title, url: flow.book.coverURL, width: 28, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(flow.book.title)
                    .font(Theme.Typography.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                if let author = flow.book.author, !author.isEmpty {
                    Text(author)
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Change", action: onChangeBook)
                .font(Theme.Typography.sans(12, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }

    private var highlightsHeader: some View {
        HStack {
            SectionLabel(highlightCountLabel)
            Spacer()
            Button {
                flow.addBlankHighlight()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add highlight")
                }
                .font(Theme.Typography.sans(12))
                .foregroundStyle(Theme.Palette.inkSoft)
            }
            .disabled(flow.stage == .submitting)
        }
        .padding(.horizontal, 8)
    }

    private var highlightCountLabel: String {
        let n = flow.highlights.count
        return "\(n) HIGHLIGHT\(n == 1 ? "" : "S") DETECTED"
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Theme.Palette.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 32)
            VStack {
                Button {
                    Task { await onSave() }
                } label: {
                    HStack(spacing: 10) {
                        if flow.stage == .submitting {
                            ProgressView().tint(Theme.Palette.bg)
                        } else {
                            Text(saveButtonTitle)
                            Text("→ READWISE")
                                .font(Theme.Typography.mono(11))
                                .tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: flow.canSave && flow.stage != .submitting))
                .disabled(!flow.canSave || flow.stage == .submitting)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .padding(.top, 4)
            .background(Theme.Palette.bg)
        }
    }

    private var saveButtonTitle: String {
        let count = flow.savableHighlights.count
        if count <= 1 { return "Save highlight" }
        return "Save \(count) highlights"
    }
}

// MARK: - Highlight card

private struct HighlightCard: View {
    @ObservedObject var flow: CaptureFlow
    @Binding var highlight: CaptureFlow.EditableHighlight
    let index: Int
    let showMerge: Bool
    let canRemove: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showMerge {
                Button { flow.mergeHighlight(at: index) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Merge with above")
                            .font(Theme.Typography.sans(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.bottom, 8)
                }
                .disabled(flow.stage == .submitting)
            }

            HStack(alignment: .center, spacing: 8) {
                SectionLabel("HIGHLIGHT \(index + 1)")
                Spacer()
                Text("P.")
                    .font(Theme.Typography.mono(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.muted)
                pageNumberChip
                if canRemove {
                    Button { flow.removeHighlight(id: highlight.id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.muted)
                            .frame(width: 28, height: 28)
                    }
                    .disabled(flow.stage == .submitting)
                }
            }
            .padding(.bottom, 10)

            TextField("Type the marked passage…", text: $highlight.text, axis: .vertical)
                .font(Theme.Typography.serif(15))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.ink)
                .textFieldStyle(.plain)

            Rectangle()
                .strokeBorder(Theme.Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .padding(.vertical, 10)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.muted)
                    .padding(.top, 4)
                TextField("Add a note…", text: $highlight.note, axis: .vertical)
                    .font(.custom("Caveat-Regular", size: 18))
                    .foregroundStyle(Theme.Palette.noteInk)
                    .textFieldStyle(.plain)
            }

        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }

    private var pageNumberChip: some View {
        TextField("—", text: $highlight.pageNumberInput)
            .keyboardType(.numberPad)
            .font(Theme.Typography.mono(12, weight: .medium))
            .foregroundStyle(Theme.Palette.ink)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Theme.Palette.bgAlt, in: RoundedRectangle(cornerRadius: Theme.Layout.pageChipRadius))
    }
}
#endif
