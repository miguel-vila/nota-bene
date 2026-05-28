import Foundation

public struct NotionOAuthConfig: Sendable, Equatable {
    public let clientID: String
    public let workerBaseURL: URL
    public let appRedirectScheme: String
    public let workerRedirectURI: String

    public init(
        clientID: String,
        workerBaseURL: URL,
        appRedirectScheme: String,
        workerRedirectURI: String
    ) {
        self.clientID = clientID
        self.workerBaseURL = workerBaseURL
        self.appRedirectScheme = appRedirectScheme
        self.workerRedirectURI = workerRedirectURI
    }
}

public struct NotionTokenResponse: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let botID: String
    public let workspaceID: String
    public let workspaceName: String?
    public let workspaceIcon: String?
    public let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case botID = "bot_id"
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceIcon = "workspace_icon"
        case refreshToken = "refresh_token"
    }

    public init(
        accessToken: String,
        botID: String,
        workspaceID: String,
        workspaceName: String? = nil,
        workspaceIcon: String? = nil,
        refreshToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.botID = botID
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.workspaceIcon = workspaceIcon
        self.refreshToken = refreshToken
    }
}

public enum NotionOAuthError: Error, Equatable {
    case invalidRedirect
    case stateMismatch
    case userCancelled
    case providerError(code: String, description: String?)
    case requestFailed(status: Int, body: String)
    case decoding(reason: String)
}

public actor NotionOAuth {
    public struct AuthorizeURL: Sendable, Equatable {
        public let url: URL
        public let state: String
    }

    private let config: NotionOAuthConfig
    private let http: HTTPClient

    public init(config: NotionOAuthConfig, http: HTTPClient = URLSession.shared) {
        self.config = config
        self.http = http
    }

    public func makeAuthorizeURL(state: String? = nil) throws -> AuthorizeURL {
        let stateValue = state ?? Self.generateState()
        guard var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize") else {
            throw NotionOAuthError.invalidRedirect
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: config.workerRedirectURI),
            URLQueryItem(name: "state", value: stateValue)
        ]
        guard let url = components.url else {
            throw NotionOAuthError.invalidRedirect
        }
        return AuthorizeURL(url: url, state: stateValue)
    }

    public func parseRedirect(_ url: URL, expectedState: String) throws -> String {
        let expectedScheme = URL(string: config.appRedirectScheme)?.scheme
        guard let scheme = url.scheme, scheme == expectedScheme else {
            throw NotionOAuthError.invalidRedirect
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw NotionOAuthError.invalidRedirect
        }
        var queryDict: [String: String] = [:]
        for item in items {
            if let v = item.value { queryDict[item.name] = v }
        }
        if let providerError = queryDict["error"] {
            if providerError == "access_denied" { throw NotionOAuthError.userCancelled }
            throw NotionOAuthError.providerError(
                code: providerError,
                description: queryDict["error_description"]
            )
        }
        guard let code = queryDict["code"] else {
            throw NotionOAuthError.invalidRedirect
        }
        guard queryDict["state"] == expectedState else {
            throw NotionOAuthError.stateMismatch
        }
        return code
    }

    public func exchange(code: String) async throws -> NotionTokenResponse {
        let url = config.workerBaseURL.appendingPathComponent("/oauth/notion/exchange")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "code": code,
            "redirect_uri": config.workerRedirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw NotionOAuthError.requestFailed(status: -1, body: "")
        }
        guard 200..<300 ~= httpResp.statusCode else {
            throw NotionOAuthError.requestFailed(
                status: httpResp.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        do {
            return try JSONDecoder().decode(NotionTokenResponse.self, from: data)
        } catch {
            throw NotionOAuthError.decoding(reason: error.localizedDescription)
        }
    }

    public static func generateState() -> String {
        UUID().uuidString
    }
}

extension NotionOAuthConfig {
    public static func fromMainBundle() -> NotionOAuthConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let clientID = info["NotionClientID"] as? String, !clientID.isEmpty,
              let workerURLString = info["NotionWorkerBaseURL"] as? String,
              let workerURL = URL(string: workerURLString),
              workerURL.scheme == "https" else {
            return nil
        }
        let scheme = (info["NotionAppRedirectScheme"] as? String) ?? "notabene://oauth/notion/callback"
        let workerRedirect = workerURL
            .appendingPathComponent("/oauth/notion/callback")
            .absoluteString
        return NotionOAuthConfig(
            clientID: clientID,
            workerBaseURL: workerURL,
            appRedirectScheme: scheme,
            workerRedirectURI: workerRedirect
        )
    }
}
