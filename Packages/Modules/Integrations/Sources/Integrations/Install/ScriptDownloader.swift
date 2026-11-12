import Foundation
import os

/// One HTTP(S) response of a link install (Story 12.9).
public struct ScriptDownload: Equatable, Sendable {
    public var data: Data
    public var statusCode: Int
    /// The URL that answered, after redirects.
    public var url: URL

    public init(data: Data, statusCode: Int, url: URL) {
        self.data = data
        self.statusCode = statusCode
        self.url = url
    }
}

/// Why a download did not return a response.
public enum ScriptDownloadError: Error, Equatable, Sendable {
    /// A redirect to a URL that is not `https` was refused.
    case insecureRedirect
    /// The body is larger than the cap.
    case tooLarge(limit: Int)
    /// A transport failure (offline, DNS, TLS, timeout), with the system's description.
    case network(String)
}

/// The only network path of the integrations module (AD-16 amended 2026-11-06: script install and update fetches,
/// user-initiated, HTTPS only). Tests inject a fake; there is no network in tests.
public protocol ScriptDownloading: Sendable {
    /// GETs `url` (HTTPS; the caller checks the scheme) and returns at most `maxBytes` of body. Throws
    /// ``ScriptDownloadError``. Non-2xx statuses are returned, not thrown.
    func download(_ url: URL, maxBytes: Int) async throws -> ScriptDownload
}

/// ``ScriptDownloading`` on an ephemeral `URLSession` (no cookies, cache or credentials on disk): refuses any
/// redirect away from `https`, stops reading past the cap.
public struct URLSessionScriptDownloader: ScriptDownloading {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public func download(_ url: URL, maxBytes: Int) async throws -> ScriptDownload {
        let guardian = RedirectGuard()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: guardian)
        } catch {
            if guardian.refused { throw ScriptDownloadError.insecureRedirect }
            throw ScriptDownloadError.network(error.localizedDescription)
        }
        if guardian.refused { throw ScriptDownloadError.insecureRedirect }
        guard let http = response as? HTTPURLResponse else { throw ScriptDownloadError.network("not HTTP") }
        let finalURL = http.url ?? url
        guard (200..<300).contains(http.statusCode) else {
            return ScriptDownload(data: Data(), statusCode: http.statusCode, url: finalURL)
        }
        if http.expectedContentLength > Int64(maxBytes) { throw ScriptDownloadError.tooLarge(limit: maxBytes) }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw ScriptDownloadError.tooLarge(limit: maxBytes) }
            }
        } catch let error as ScriptDownloadError {
            throw error
        } catch {
            throw ScriptDownloadError.network(error.localizedDescription)
        }
        return ScriptDownload(data: data, statusCode: http.statusCode, url: finalURL)
    }
}

/// Follows `https` redirects only; anything else ends the request on the redirect response.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var refused: Bool { state.withLock { $0 } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.scheme?.lowercased() == "https" else {
            state.withLock { $0 = true }
            task.cancel()
            return nil
        }
        return request
    }
}
