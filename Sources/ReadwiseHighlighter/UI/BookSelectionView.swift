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
            List {
                if query.isEmpty && !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { book in
                            BookRow(book: book) { select(book) }
                        }
                    }
                }
                if !libraryMatches.isEmpty {
                    Section("In your library") {
                        ForEach(libraryMatches) { book in
                            BookRow(book: book) { select(book) }
                        }
                    }
                }
                if !openLibraryMatches.isEmpty {
                    Section("New book") {
                        ForEach(openLibraryMatches) { book in
                            BookRow(book: book) { select(book) }
                        }
                    }
                }
                if openLibrarySearching {
                    HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                }
                if let libraryError {
                    Text(libraryError).foregroundStyle(.red).font(.footnote)
                }
                Section {
                    Button {
                        manualEntry = ManualEntry()
                    } label: {
                        Label("Add book manually", systemImage: "plus.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search books")
            .navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .refreshable { await refreshLibrary(force: true) }
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
                CoverThumbnail(url: book.coverURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.body).foregroundStyle(.primary)
                    if let author = book.author, !author.isEmpty {
                        Text(author).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CoverThumbnail: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().controlSize(.mini)
                    case .failure:
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 52)
    }
}

private struct ManualBookEntryView: View {
    var onSave: (Book) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Required", text: $title)
                }
                Section("Author") {
                    TextField("Optional", text: $author)
                }
            }
            .navigationTitle("Add book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id = "manual:\(UUID().uuidString)"
                        let book = Book(
                            id: id,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : author.trimmingCharacters(in: .whitespacesAndNewlines),
                            source: .manual
                        )
                        onSave(book)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif
