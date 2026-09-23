import Foundation

actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    private let baseURL = URL(string: "http://10.67.50.19:8000/api")!
    #else
    private let baseURL = URL(string: "https://your-production-url.com/api")!
    #endif

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - GET

    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - POST

    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - SSE stream (POST /chat/stream)

    nonisolated func chatStream(
        message: String,
        sessionId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = await baseURL.appendingPathComponent("chat/stream")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 120

                    let payload = ChatStreamRequest(
                        message: message,
                        sessionId: sessionId
                    )
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        throw APIError.requestFailed
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        if let data = payload.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(
                               ChatChunk.self, from: data
                           ) {
                            continuation.yield(chunk.content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    func fetchStocks() async throws -> [BackendStockSummary] {
        let response: BackendStockListResponse = try await get("stocks")
        return response.stocks
    }

    func fetchStockDetail(ticker: String) async throws -> BackendStockDetail {
        let clean = ticker.components(separatedBy: ".").first ?? ticker
        return try await get("stock/\(clean)")
    }

    func fetchMarketOverview() async throws -> BackendMarketOverview {
        return try await get("market-overview")
    }
}

// MARK: - Chat DTOs

struct ChatStreamRequest: Encodable {
    let message: String
    let sessionId: UUID

    enum CodingKeys: String, CodingKey {
        case message
        case sessionId = "session_id"
    }
}

struct ChatChunk: Decodable {
    let content: String
}

struct ChatResponse: Decodable {
    let sessionId: UUID
    let response: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case response
    }
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Request failed"
        case .decodingFailed: "Failed to decode response"
        }
    }
}
