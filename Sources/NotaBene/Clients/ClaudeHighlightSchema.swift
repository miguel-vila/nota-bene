import Foundation

/// Single source of truth for the per-highlight schema we ask Claude to emit.
/// `ClaudeClient.makeBody` reads `inputSchema` for the tool definition, and
/// `ClaudeHighlightArrayParser` reads `fields` to recover stringified payloads
/// when strict JSON parsing fails — adding or renaming a field updates both
/// sides at once.
public enum ClaudeHighlightSchema {
    public enum Kind {
        case string
        case nullableString
        case nullableInt

        var jsonSchemaType: Any {
            switch self {
            case .string: return "string"
            case .nullableString: return ["string", "null"]
            case .nullableInt: return ["integer", "null"]
            }
        }
    }

    public struct Field {
        public let name: String
        public let kind: Kind
    }

    public static let fields: [Field] = [
        .init(name: "text", kind: .string),
        .init(name: "page_number", kind: .nullableInt),
        .init(name: "note", kind: .nullableString),
    ]

    public static var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "highlights": [
                    "type": "array",
                    "items": itemSchema
                ]
            ],
            "required": ["highlights"]
        ]
    }

    private static var itemSchema: [String: Any] {
        var properties: [String: Any] = [:]
        for field in fields {
            properties[field.name] = ["type": field.kind.jsonSchemaType]
        }
        return [
            "type": "object",
            "properties": properties,
            "required": fields.map { $0.name }
        ]
    }
}
