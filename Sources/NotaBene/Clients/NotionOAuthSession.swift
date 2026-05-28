#if canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import Foundation
import UIKit

@MainActor
public final class NotionOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let oauth: NotionOAuth
    private let appRedirectScheme: String

    public init(oauth: NotionOAuth, appRedirectScheme: String) {
        self.oauth = oauth
        self.appRedirectScheme = appRedirectScheme
        super.init()
    }

    public func connect() async throws -> NotionTokenResponse {
        let authorize = try await oauth.makeAuthorizeURL()
        let callbackScheme = URL(string: appRedirectScheme)?.scheme ?? "notabene"
        let redirectURL = try await runWebAuthSession(
            authorizeURL: authorize.url,
            callbackScheme: callbackScheme
        )
        let code = try await oauth.parseRedirect(redirectURL, expectedState: authorize.state)
        return try await oauth.exchange(code: code)
    }

    private func runWebAuthSession(
        authorizeURL: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let asError = error as? ASWebAuthenticationSessionError,
                          asError.code == .canceledLogin {
                    continuation.resume(throwing: NotionOAuthError.userCancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NotionOAuthError.invalidRedirect)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: NotionOAuthError.invalidRedirect)
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
#endif
