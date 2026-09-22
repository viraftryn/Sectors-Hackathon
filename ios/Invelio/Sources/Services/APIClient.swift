import Foundation

actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    private let baseURL = URL(string: "http://localhost:8000/api")!
    #else
    private let baseURL = URL(string: "https://your-production-url.com/api")!
    #endif

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
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
