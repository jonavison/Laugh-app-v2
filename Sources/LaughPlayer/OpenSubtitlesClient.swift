import Foundation

/// One searchable / downloadable subtitle hit from OpenSubtitles.com.
struct OpenSubtitlesSearchResult: Equatable, Identifiable {
    var id: String { "\(fileID)" }
    let fileID: Int
    let fileName: String
    let language: String
    let release: String
    let title: String
    let downloadCount: Int
    let rating: Double?
}

enum OpenSubtitlesClientError: Error, Equatable {
    case missingApiKey
    case noVideoOpen
    case badHTTPStatus(Int, String?)
    case quotaExhausted
    case decodeFailed(String)
    case emptyResults
    case downloadLinkMissing
    case network(String)

    var userMessage: String {
        switch self {
        case .missingApiKey:
            return OpenSubtitlesConfig.missingKeyMessage()
        case .noVideoOpen:
            return "Open a video first, then search for subtitles."
        case .quotaExhausted:
            return "OpenSubtitles download limit reached for today. Try again tomorrow, or create a free account for a higher quota."
        case .badHTTPStatus(let code, let detail):
            if code == 401 || code == 403 {
                return "OpenSubtitles rejected the Api-Key. Check Packaging/opensubtitles-api-key.local or OPENSUBTITLES_API_KEY."
            }
            if let detail, !detail.isEmpty {
                return "OpenSubtitles error (\(code)): \(detail)"
            }
            return "OpenSubtitles request failed (HTTP \(code))."
        case .decodeFailed:
            return "Couldn't read the OpenSubtitles response."
        case .emptyResults:
            return "No subtitles found. Try a shorter query or another language."
        case .downloadLinkMissing:
            return "OpenSubtitles did not return a download link."
        case .network(let message):
            return "Network error: \(message)"
        }
    }

    static func classifyHTTP(status: Int, body: String?) -> OpenSubtitlesClientError {
        if status == 406 || status == 429 {
            return .quotaExhausted
        }
        // OpenSubtitles sometimes returns 401 for bad key, 403 for quota-ish blocks.
        if status == 401 {
            return .badHTTPStatus(status, body)
        }
        if let body, body.lowercased().contains("download limit") {
            return .quotaExhausted
        }
        return .badHTTPStatus(status, truncated(body))
    }

    private static func truncated(_ body: String?) -> String? {
        guard let body else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(180))
    }
}

/// Anonymous OpenSubtitles.com REST client (Api-Key only; no user login).
final class OpenSubtitlesClient: @unchecked Sendable {
    private let session: URLSession
    private let apiKeyProvider: () -> String?
    private let userAgentProvider: () -> String
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.opensubtitles.com/api/v1")!,
        apiKeyProvider: @escaping () -> String? = { OpenSubtitlesConfig.apiKey() },
        userAgentProvider: @escaping () -> String = { OpenSubtitlesConfig.userAgent() }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
        self.userAgentProvider = userAgentProvider
    }

    func search(query: String, language: String) async throws -> [OpenSubtitlesSearchResult] {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw OpenSubtitlesClientError.missingApiKey
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "languages", value: language),
            URLQueryItem(name: "query", value: trimmed)
        ]
        guard let url = components.url else {
            throw OpenSubtitlesClientError.network("Invalid search URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, apiKey: apiKey)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesClientError.network("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenSubtitlesClientError.classifyHTTP(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        return try Self.parseSearchResults(data)
    }

    /// Returns a temporary download URL and suggested file name from OpenSubtitles.
    func requestDownload(fileID: Int) async throws -> (link: URL, fileName: String?) {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw OpenSubtitlesClientError.missingApiKey
        }
        let url = baseURL.appendingPathComponent("download")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileID])

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesClientError.network("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenSubtitlesClientError.classifyHTTP(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        guard let parsed = try Self.parseDownloadResponse(data),
              let link = URL(string: parsed.link) else {
            throw OpenSubtitlesClientError.downloadLinkMissing
        }
        return (link, parsed.fileName)
    }

    func downloadFile(from link: URL) async throws -> Data {
        var request = URLRequest(url: link)
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenSubtitlesClientError.classifyHTTP(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        return data
    }

    // MARK: - Parsing (testable)

    static func parseSearchResults(_ data: Data) throws -> [OpenSubtitlesSearchResult] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OpenSubtitlesClientError.decodeFailed(error.localizedDescription)
        }
        guard let root = json as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            throw OpenSubtitlesClientError.decodeFailed("missing data array")
        }

        var results: [OpenSubtitlesSearchResult] = []
        for item in items {
            guard let attributes = item["attributes"] as? [String: Any] else { continue }
            let language = (attributes["language"] as? String) ?? ""
            let release = (attributes["release"] as? String) ?? ""
            let downloadCount = (attributes["download_count"] as? Int)
                ?? (attributes["download_count"] as? Double).map(Int.init)
                ?? 0
            let rating = attributes["ratings"] as? Double
            let feature = attributes["feature_details"] as? [String: Any]
            let title = (feature?["title"] as? String)
                ?? (feature?["movie_name"] as? String)
                ?? release
            guard let files = attributes["files"] as? [[String: Any]],
                  let first = files.first,
                  let fileID = first["file_id"] as? Int
                    ?? (first["file_id"] as? Double).map(Int.init) else {
                continue
            }
            let fileName = (first["file_name"] as? String) ?? release
            results.append(
                OpenSubtitlesSearchResult(
                    fileID: fileID,
                    fileName: fileName,
                    language: language,
                    release: release,
                    title: title,
                    downloadCount: downloadCount,
                    rating: rating
                )
            )
        }
        return results
    }

    static func parseDownloadResponse(_ data: Data) throws -> (link: String, fileName: String?)? {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OpenSubtitlesClientError.decodeFailed(error.localizedDescription)
        }
        guard let root = json as? [String: Any],
              let link = root["link"] as? String,
              !link.isEmpty else {
            return nil
        }
        let fileName = root["file_name"] as? String
        return (link, fileName)
    }

    // MARK: - Transport

    private func applyHeaders(_ request: inout URLRequest, apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgentProvider(), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw OpenSubtitlesClientError.network(error.localizedDescription)
        }
    }
}

/// Languages offered in the search sheet (ISO 639-1 codes OpenSubtitles accepts).
enum OpenSubtitlesLanguage: String, CaseIterable {
    case en, fr, es, de, it, pt, nl

    var menuTitle: String {
        switch self {
        case .en: return "English"
        case .fr: return "French"
        case .es: return "Spanish"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .nl: return "Dutch"
        }
    }
}
