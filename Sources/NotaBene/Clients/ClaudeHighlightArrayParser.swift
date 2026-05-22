import Foundation

/// Schema-aware structural parser for the highlights array when Claude emits
/// it as a JSON-encoded string with stray quotes that `JSONSerialization`
/// can't decode. Locates each known key from `ClaudeHighlightSchema` inside an
/// object segment and treats the run between two adjacent keys as that
/// field's raw value, so a stray `"` inside a `text` body no longer desyncs
/// the parser the way the character-walker in `JSONRepair` can.
public enum ClaudeHighlightArrayParser {
    public static func parse(_ source: String) -> [[String: Any]]? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
        let segments = splitTopLevelObjects(inner)
        guard !segments.isEmpty else { return nil }

        var results: [[String: Any]] = []
        for segment in segments {
            if let obj = parseObject(segment) {
                results.append(obj)
            }
        }
        return results.isEmpty ? nil : results
    }

    private static func splitTopLevelObjects(_ inner: String) -> [String] {
        var segments: [String] = []
        var depth = 0
        var start: String.Index? = nil
        var i = inner.startIndex
        while i < inner.endIndex {
            let c = inner[i]
            if c == "{" {
                if depth == 0 { start = inner.index(after: i) }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let st = start {
                    segments.append(String(inner[st..<i]))
                    start = nil
                }
            }
            i = inner.index(after: i)
        }
        return segments
    }

    private struct LocatedField {
        let field: ClaudeHighlightSchema.Field
        let keyStart: String.Index
        let valueStart: String.Index
    }

    private static func parseObject(_ segment: String) -> [String: Any]? {
        var located: [LocatedField] = []
        for field in ClaudeHighlightSchema.fields {
            guard let valueStart = locateValueStart(of: field.name, in: segment),
                  let keyRange = segment.range(of: "\"\(field.name)\"")
            else { continue }
            located.append(LocatedField(field: field, keyStart: keyRange.lowerBound, valueStart: valueStart))
        }
        located.sort { $0.keyStart < $1.keyStart }
        guard !located.isEmpty else { return nil }

        var result: [String: Any] = [:]
        for (i, loc) in located.enumerated() {
            let valueEnd = (i + 1 < located.count) ? located[i + 1].keyStart : segment.endIndex
            let raw = String(segment[loc.valueStart..<valueEnd])
            if let value = parseValue(raw, kind: loc.field.kind) {
                result[loc.field.name] = value
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func locateValueStart(of key: String, in segment: String) -> String.Index? {
        guard let keyRange = segment.range(of: "\"\(key)\"") else { return nil }
        var c = keyRange.upperBound
        while c < segment.endIndex, segment[c].isWhitespace { c = segment.index(after: c) }
        guard c < segment.endIndex, segment[c] == ":" else { return nil }
        c = segment.index(after: c)
        while c < segment.endIndex, segment[c].isWhitespace { c = segment.index(after: c) }
        return c
    }

    private static func parseValue(_ raw: String, kind: ClaudeHighlightSchema.Kind) -> Any? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r,"))
        switch kind {
        case .string:
            return unquote(trimmed)
        case .nullableString:
            if trimmed == "null" { return NSNull() }
            return unquote(trimmed)
        case .nullableInt:
            if trimmed == "null" { return NSNull() }
            return Int(trimmed)
        }
    }

    private static func unquote(_ s: String) -> String? {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return nil }
        let body = String(s.dropFirst().dropLast())
        return unescapeJSON(body)
    }

    private static func unescapeJSON(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var iter = s.makeIterator()
        while let c = iter.next() {
            if c == "\\" {
                guard let n = iter.next() else { result.append(c); break }
                switch n {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                default:
                    result.append("\\")
                    result.append(n)
                }
            } else {
                result.append(c)
            }
        }
        return result
    }
}
