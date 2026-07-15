import Foundation

nonisolated enum ProviderNetworkSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }

    static func validateHTTPS(_ request: URLRequest, allowedHost: String) throws {
        guard let url = request.url,
            url.scheme?.lowercased() == "https",
            url.host?.lowercased() == allowedHost.lowercased()
        else {
            throw ProviderConnectionError.networkFailure(
                "The provider request was blocked because its destination was not allowed."
            )
        }
    }
}
