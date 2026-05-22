import Foundation

public enum LLMProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case gemini
    case claude

    public static let `default`: LLMProvider = .gemini

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return GeminiClient.defaultModel
        case .claude: return ClaudeClient.defaultModel
        }
    }

    public struct ModelOption: Identifiable, Hashable, Sendable {
        public let rawValue: String
        public let label: String
        public var id: String { rawValue }

        public init(rawValue: String, label: String) {
            self.rawValue = rawValue
            self.label = label
        }
    }

    public var presets: [ModelOption] {
        switch self {
        case .gemini:
            return GeminiClient.ModelPreset.allCases.map {
                ModelOption(rawValue: $0.rawValue, label: $0.label)
            }
        case .claude:
            return ClaudeClient.ModelPreset.allCases.map {
                ModelOption(rawValue: $0.rawValue, label: $0.label)
            }
        }
    }
}
