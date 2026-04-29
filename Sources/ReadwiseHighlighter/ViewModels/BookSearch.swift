import Foundation

public enum BookSearch {
    /// Merge Readwise (preferred) + Open Library results, deduping by (title, author).
    /// Readwise entries appear first; duplicates from Open Library are dropped.
    public static func merge(readwise: [Book], openLibrary: [Book]) -> [Book] {
        var seen = Set<String>()
        var out: [Book] = []
        for b in readwise where seen.insert(b.dedupKey).inserted {
            out.append(b)
        }
        for b in openLibrary where seen.insert(b.dedupKey).inserted {
            out.append(b)
        }
        return out
    }

    /// Case-insensitive substring match across title and author.
    public static func filterLibrary(_ books: [Book], query: String) -> [Book] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return books.filter { b in
            b.title.lowercased().contains(q)
                || (b.author ?? "").lowercased().contains(q)
        }
    }
}
