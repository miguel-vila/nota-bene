#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct BookSelectionView: View {
    @EnvironmentObject private var state: AppState
    @State private var query: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var libraryMatches: [Book] = []
    @State private var openLibraryMatches: [Book] = []
    @State private var recents: [Book] = []
    @State private var libraryLoaded: Bool = false
    @State private var libraryRefreshing: Bool = false
    @State private var libraryError: String?
    @State private var openLibrarySearching: Bool = false
    @State private var manualEntry: ManualEntry?
    @State private var selection: Book?
    @State private var showSettings = false

    private struct ManualEntry: Identifiable {
        let id = UUID()
    }

    public init() {}

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
                            if query.isEmpty && !recents.isEmpty {
                                section("RECENT", rows: recents)
                            }
                            if !libraryMatches.isEmpty {
                                section("IN YOUR LIBRARY", rows: libraryMatches)
                            }
                            if !openLibraryMatches.isEmpty {
                                section("NEW BOOK", rows: openLibraryMatches)
                            }
                            if openLibrarySearching {
                                HStack(spacing: 8) {
                                    ProgressView().tint(Theme.Palette.muted)
                                    Text("Searching…")
                                        .font(Theme.Typography.sans(13))
                                        .foregroundStyle(Theme.Palette.muted)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                            }
                            if let libraryError {
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
                    .refreshable { await refreshLibrary(force: true) }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selection) { book in
                CaptureFlowContainer(book: book)
                    .environmentObject(state)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(state)
            }
            .sheet(item: $manualEntry) { _ in
                ManualBookEntryView { book in
                    manualEntry = nil
                    select(book)
                }
            }
            .onAppear {
                Task { await loadInitial() }
            }
            .onChange(of: query) { _, newValue in
                debounceSearch(query: newValue)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("ReadwiseHighlighter")
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
            TextField("Title or author", text: $query)
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
                BookRow(book: book) { select(book) }
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

    private func select(_ book: Book) {
        Task {
            try? await state.bookStore.recordUsage(of: book)
            recents = await state.bookStore.state.recents
        }
        selection = book
    }

    private func loadInitial() async {
        let cache = await state.bookStore.state
        recents = cache.recents
        libraryMatches = []
        if cache.library.isEmpty {
            await refreshLibrary(force: true)
        } else {
            libraryLoaded = true
            let needs = await state.bookStore.libraryNeedsRefresh(maxAgeHours: state.libraryRefreshIntervalHours)
            if needs { await refreshLibrary(force: false) }
        }
    }

    private func refreshLibrary(force: Bool) async {
        guard let client = state.currentReadwiseClient() else { return }
        if libraryRefreshing && !force { return }
        libraryRefreshing = true
        defer { libraryRefreshing = false }
        do {
            let books = try await client.listBooks()
            try await state.bookStore.setLibrary(books)
            libraryLoaded = true
            libraryError = nil
            recomputeMatches()
        } catch ReadwiseError.invalidToken {
            libraryError = "Readwise token rejected — update it in Settings."
        } catch {
            libraryError = "Couldn't refresh library: \(error.localizedDescription)"
        }
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await runSearch(query: query)
        }
    }

    private func runSearch(query: String) async {
        recomputeMatches()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            openLibraryMatches = []
            return
        }
        openLibrarySearching = true
        defer { openLibrarySearching = false }
        do {
            let results = try await state.openLibrary.search(query: trimmed)
            if Task.isCancelled { return }
            openLibraryMatches = BookSearch.merge(readwise: libraryMatches, openLibrary: results)
                .filter { $0.source != .readwise }
        } catch {
            openLibraryMatches = []
        }
    }

    private func recomputeMatches() {
        let cache = state.bookStore
        Task {
            let library = await cache.state.library
            libraryMatches = BookSearch.filterLibrary(library, query: query)
        }
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
