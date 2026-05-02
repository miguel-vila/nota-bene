import Foundation

/// Best-effort repair for a specific malformed-JSON pattern we've observed in
/// Claude tool-use responses: inside a JSON string value, an inner quoted
/// phrase is emitted with bare `"` characters instead of `\"`, producing
/// structurally-valid punctuation but an unparseable string body.
///
/// The repair walks the source character-by-character, tracking whether the
/// cursor is inside a JSON string. When inside, a `"` is treated as the
/// string closer only if the next non-whitespace character is a JSON
/// structural token (`,`, `:`, `]`, `}`); otherwise the quote is escaped.
/// This handles the common failure shape but is a heuristic — it can
/// mis-judge a string whose contents end with an inner quote immediately
/// before a real comma.
public enum JSONRepair {
    public static func escapeStrayQuotes(in source: String) -> String {
        var result = ""
        result.reserveCapacity(source.count)
        let chars = Array(source)
        var i = 0
        var insideString = false
        while i < chars.count {
            let c = chars[i]
            if insideString {
                if c == "\\", i + 1 < chars.count {
                    result.append(c)
                    result.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" {
                    if isLikelyStringCloser(after: i, in: chars) {
                        result.append(c)
                        insideString = false
                    } else {
                        result.append("\\")
                        result.append("\"")
                    }
                    i += 1
                    continue
                }
                result.append(c)
                i += 1
            } else {
                result.append(c)
                if c == "\"" {
                    insideString = true
                }
                i += 1
            }
        }
        return result
    }

    public static func parseLeniently(_ source: String) -> Any? {
        let repaired = escapeStrayQuotes(in: source)
        guard let data = repaired.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func isLikelyStringCloser(after index: Int, in chars: [Character]) -> Bool {
        var j = index + 1
        while j < chars.count, chars[j].isWhitespace {
            j += 1
        }
        guard j < chars.count else { return true }
        switch chars[j] {
        case ",", ":", "}", "]":
            return true
        default:
            return false
        }
    }
}
