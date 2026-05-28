import XCTest
@testable import NotaBene

final class NotionOAuthTests: XCTestCase {
    private func makeConfig() -> NotionOAuthConfig {
        NotionOAuthConfig(
            clientID: "client-abc",
            workerBaseURL: URL(string: "https://worker.example")!,
            appRedirectScheme: "notabene://oauth/notion/callback",
            workerRedirectURI: "https://worker.example/oauth/notion/callback"
        )
    }

    func test_makeAuthorizeURL_includesExpectedQueryItems() async throws {
        let oauth = NotionOAuth(config: makeConfig())
        let result = try await oauth.makeAuthorizeURL(state: "fixed-state")
        let comps = try XCTUnwrap(URLComponents(url: result.url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(comps.host, "api.notion.com")
        XCTAssertEqual(comps.path, "/v1/oauth/authorize")
        XCTAssertEqual(items["client_id"], "client-abc")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["owner"], "user")
        XCTAssertEqual(items["redirect_uri"], "https://worker.example/oauth/notion/callback")
        XCTAssertEqual(items["state"], "fixed-state")
        XCTAssertEqual(result.state, "fixed-state")
    }

    func test_makeAuthorizeURL_generatesStateWhenNotProvided() async throws {
        let oauth = NotionOAuth(config: makeConfig())
        let a = try await oauth.makeAuthorizeURL()
        let b = try await oauth.makeAuthorizeURL()
        XCTAssertFalse(a.state.isEmpty)
        XCTAssertNotEqual(a.state, b.state)
    }

    func test_parseRedirect_acceptsValidCallback() async throws {
        let oauth = NotionOAuth(config: makeConfig())
        let url = URL(string: "notabene://oauth/notion/callback?code=abc123&state=expected")!
        let code = try await oauth.parseRedirect(url, expectedState: "expected")
        XCTAssertEqual(code, "abc123")
    }

    func test_parseRedirect_rejectsStateMismatch() async {
        let oauth = NotionOAuth(config: makeConfig())
        let url = URL(string: "notabene://oauth/notion/callback?code=abc&state=other")!
        do {
            _ = try await oauth.parseRedirect(url, expectedState: "expected")
            XCTFail("expected throw")
        } catch NotionOAuthError.stateMismatch {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_parseRedirect_treatsAccessDeniedAsUserCancelled() async {
        let oauth = NotionOAuth(config: makeConfig())
        let url = URL(string: "notabene://oauth/notion/callback?error=access_denied&state=x")!
        do {
            _ = try await oauth.parseRedirect(url, expectedState: "x")
            XCTFail("expected throw")
        } catch NotionOAuthError.userCancelled {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_parseRedirect_surfacesProviderError() async {
        let oauth = NotionOAuth(config: makeConfig())
        let url = URL(string: "notabene://oauth/notion/callback?error=invalid_request&error_description=bad&state=x")!
        do {
            _ = try await oauth.parseRedirect(url, expectedState: "x")
            XCTFail("expected throw")
        } catch let NotionOAuthError.providerError(code, description) {
            XCTAssertEqual(code, "invalid_request")
            XCTAssertEqual(description, "bad")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_parseRedirect_rejectsForeignScheme() async {
        let oauth = NotionOAuth(config: makeConfig())
        let url = URL(string: "evil://oauth/notion/callback?code=abc&state=x")!
        do {
            _ = try await oauth.parseRedirect(url, expectedState: "x")
            XCTFail("expected throw")
        } catch NotionOAuthError.invalidRedirect {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_exchange_postsCodeAndRedirectToWorker() async throws {
        let resp = """
        {
          "access_token": "secret_x",
          "bot_id": "bot-1",
          "workspace_id": "ws-1",
          "workspace_name": "Library WS",
          "workspace_icon": "https://img.example/icon.png"
        }
        """.data(using: .utf8)!

        let mock = MockHTTPClient { _ in MockHTTPClient.ok(resp) }
        let oauth = NotionOAuth(config: makeConfig(), http: mock)
        let token = try await oauth.exchange(code: "auth-code-1")
        XCTAssertEqual(token.accessToken, "secret_x")
        XCTAssertEqual(token.botID, "bot-1")
        XCTAssertEqual(token.workspaceID, "ws-1")
        XCTAssertEqual(token.workspaceName, "Library WS")

        let req = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://worker.example/oauth/notion/exchange")
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["code"], "auth-code-1")
        XCTAssertEqual(json["redirect_uri"], "https://worker.example/oauth/notion/callback")
    }

    func test_exchange_throwsRequestFailedOnNon2xx() async {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(500, data: Data("oops".utf8)) }
        let oauth = NotionOAuth(config: makeConfig(), http: mock)
        do {
            _ = try await oauth.exchange(code: "x")
            XCTFail("expected throw")
        } catch let NotionOAuthError.requestFailed(status, body) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(body, "oops")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
