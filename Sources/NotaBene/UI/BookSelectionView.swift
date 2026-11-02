#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct BookSelectionView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var selection: BookSelection
    @State private var manualEntry: ManualEntry?
    @State private var showSettings = false

    private struct ManualEntry: Identifiable {
        let id = UUID()
    }

    public init(state: AppState) {
        _selection = StateObject(wrappedValue: BookSelection(
            bookStore: state.bookStore,
            openLibrary: state.openLibrary,
            readwiseClient: { state.currentReadwiseClient() }
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    headline
                    searchField
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                        .padding(.bottom, 14)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if selection.query.isEmpty && !selection.recents.isEmpty {
                                section("RECENT", rows: selection.recents)
                            }
                            if !selection.libraryMatches.isEmpty {
                                section("IN YOUR LIBRARY", rows: selection.libraryMatches)
                            }
                            if !selection.openLibraryMatches.isEmpty {
                                section("NEW BOOK", rows: selection.openLibraryMatches)
                            }
                            if selection.isSearchingOpenLibrary {
                                HStack(spacing: 8) {
                                    ProgressView().tint(Theme.Palette.muted)
                                    Text("Searching…")
                                        .font(Theme.Typography.sans(13))
                                        .foregroundStyle(Theme.Palette.muted)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                            }
                            if let libraryError = selection.libraryError {
                                Text(libraryError)
                                    .font(Theme.Typography.sans(12))
                                    .foregroundStyle(Theme.Palette.danger)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                            }
                            addManuallyButton
                                .padding(.horizontal, 24)
                                .padding(.top, 18)
                                .padding(.bottom, 36)
                        }
                    }
                    .refreshable { await selection.refreshLibrary(force: true) }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selection.selectedBook) { book in
                CaptureFlowContainer(book: book)
                    .environmentObject(state)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(state)
            }
            .sheet(item: $manualEntry) { _ in
                ManualBookEntryView { book in
                    manualEntry = nil
                    selection.selectedBook = book
                }
            }
            .onAppear {
                Task { await selection.load() }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Nota Bene")
                .font(.system(size: 20, weight: .regular, design: .serif).italic())
                .kerning(-0.3)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private var headline: some View {
        Text("What are you\nreading?")
            .font(Theme.Typography.serif(30))
            .lineSpacing(2)
            .kerning(-0.6)
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.muted)
            TextField("Title or author", text: $selection.query)
                .font(Theme.Typography.sans(15))
                .foregroundStyle(Theme.Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }

    private func section(_ label: String, rows: [Book]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(label)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 6)
            ForEach(rows) { book in
                BookRow(book: book) { selection.selectedBook = book }
                Rectangle()
                    .fill(Theme.Palette.lineSoft)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var addManuallyButton: some View {
        Button { manualEntry = ManualEntry() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add book manually")
                    .font(Theme.Typography.sans(14, weight: .medium))
            }
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                    .strokeBorder(Theme.Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BookRow: View {
    let book: Book
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CoverThumbnail(title: book.title, url: book.coverURL, width: 36, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(Theme.Typography.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(Theme.Typography.sans(12))
                            .foregroundStyle(Theme.Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailingMark
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailingMark: some View {
        switch book.source {
        case .readwise:
            EmptyView()
        case .openLibrary, .manual:
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.Palette.muted)
        }
    }
}

private struct ManualBookEntryView: View {
    var onSave: (Book) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add book")
                        .font(Theme.Typography.serif(28))
                        .kerning(-0.4)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TITLE")
                            .font(Theme.Typography.mono(10, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.muted)
                        ThemedTextField("Required", text: $title, monospaced: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AUTHOR")
                            .font(Theme.Typography.mono(10, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.muted)
                        ThemedTextField("Optional", text: $author, monospaced: false)
                    }

                    Spacer()

                    Button {
                        let book = Book(
                            id: "manual:\(UUID().uuidString)",
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : author.trimmingCharacters(in: .whitespacesAndNewlines),
                            source: .manual
                        )
                        onSave(book)
                        dismiss()
                    } label: {
                        Text("Save book")
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
        }
    }
}
#endif
