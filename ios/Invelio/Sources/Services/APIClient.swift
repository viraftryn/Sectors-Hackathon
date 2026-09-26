import Foundation
import UIKit

actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    #if targetEnvironment(simulator)
    private let baseURL = URL(string: "http://192.168.0.133:8000/api")!
    #else
    private let baseURL = URL(string: "http://0.0.0.0:8000/api")!
    #endif
    #else
    private let baseURL = URL(string: "https://your-production-url.com/api")!
    #endif

    private let session: URLSession

    nonisolated var deviceId: String {
        if let stored = UserDefaults.standard.string(forKey: "invelio_device_id") {
            return stored
        }
        let newId = UUID().uuidString.lowercased()
        UserDefaults.standard.set(newId, forKey: "invelio_device_id")
        return newId
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generic HTTP Methods

    private func buildURL(for path: String) -> URL {
        if path.contains("?") {
            let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let basePath = String(parts[0])
            let queryString = String(parts[1])
            if var components = URLComponents(url: baseURL.appendingPathComponent(basePath), resolvingAgainstBaseURL: true) {
                components.query = queryString
                if let url = components.url {
                    return url
                }
            }
        }
        return baseURL.appendingPathComponent(path)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = buildURL(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ [APIClient] GET \(path) failed (HTTP \(code)): \(errorBody)")
            throw APIError.serverError(statusCode: code, detail: errorBody)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ [APIClient] POST \(path) failed (HTTP \(code)): \(errorBody)")
            throw APIError.serverError(statusCode: code, detail: errorBody)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func patchEmpty(_ path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ [APIClient] PATCH \(path) failed (HTTP \(code)): \(errorBody)")
            throw APIError.serverError(statusCode: code, detail: errorBody)
        }
    }

    // MARK: - In-Memory Cache
    private var stockDetailCache: [String: (data: BackendStockDetail, timestamp: Date)] = [:]
    private var stocksCache: (data: [BackendStockSummary], timestamp: Date)? = nil
    private var marketIntelligenceCache: (data: BackendMarketIntelligence, timestamp: Date)? = nil
    private let defaultCacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Market & Stocks

    func fetchStocks(forceRefresh: Bool = false) async throws -> [BackendStockSummary] {
        if !forceRefresh, let cached = stocksCache, Date().timeIntervalSince(cached.timestamp) < defaultCacheTTL {
            return cached.data
        }
        let response: BackendStockListResponse = try await get("stocks")
        stocksCache = (response.stocks, Date())
        return response.stocks
    }

    func fetchStockDetail(ticker: String, forceRefresh: Bool = false) async throws -> BackendStockDetail {
        let clean = ticker.components(separatedBy: ".").first?.uppercased() ?? ticker.uppercased()
        if !forceRefresh, let cached = stockDetailCache[clean], Date().timeIntervalSince(cached.timestamp) < defaultCacheTTL {
            return cached.data
        }
        let detail: BackendStockDetail = try await get("stock/\(clean)")
        stockDetailCache[clean] = (detail, Date())
        return detail
    }

    func fetchStockInsights(ticker: String) async throws -> BackendStockInsights {
        let clean = ticker.components(separatedBy: ".").first ?? ticker
        return try await get("stock/\(clean)/insights")
    }

    func fetchMarketOverview() async throws -> BackendMarketOverview {
        return try await get("market-overview")
    }

    func fetchRecommendations() async throws -> BackendRecommendationList {
        return try await get("recommendations")
    }

    // MARK: - Market Intelligence

    func fetchMarketIntelligence(forceRefresh: Bool = false) async throws -> BackendMarketIntelligence {
        if !forceRefresh, let cached = marketIntelligenceCache, Date().timeIntervalSince(cached.timestamp) < defaultCacheTTL {
            return cached.data
        }
        let result: BackendMarketIntelligence = try await get("market-intelligence")
        marketIntelligenceCache = (result, Date())
        return result
    }

    // MARK: - Portfolio & Holdings

    func fetchPortfolio() async throws -> BackendPortfolioSummary {
        return try await get("portfolio")
    }

    func fetchHoldingLots() async throws -> [BackendHoldingLot] {
        let res: BackendHoldingLotList = try await get("portfolio/lots")
        return res.lots
    }

    func buyStock(
        id: UUID? = nil,
        ticker: String,
        pricePerShare: Double,
        shares: Double? = nil,
        totalInvested: Double? = nil,
        buyDate: Date? = nil
    ) async throws -> BackendHoldingLot {
        let isoDate: String?
        if let d = buyDate {
            let formatter = ISO8601DateFormatter()
            isoDate = formatter.string(from: d)
        } else {
            isoDate = nil
        }

        let payload = BackendHoldingLotIn(
            id: id?.uuidString.lowercased(),
            ticker: ticker.components(separatedBy: ".").first?.uppercased() ?? ticker.uppercased(),
            pricePerShare: pricePerShare,
            shares: shares,
            totalInvested: totalInvested,
            buyDate: isoDate
        )
        return try await post("portfolio/buy", body: payload)
    }

    func sellStock(
        ticker: String,
        shares: Double,
        sellPrice: Double
    ) async throws -> BackendSellResult {
        let payload = BackendSellIn(
            ticker: ticker.components(separatedBy: ".").first?.uppercased() ?? ticker.uppercased(),
            shares: shares,
            sellPrice: sellPrice
        )
        return try await post("portfolio/sell", body: payload)
    }

    func deleteLot(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("portfolio/lots/\(id.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ [APIClient] DELETE portfolio/lots failed (HTTP \(code)): \(errorBody)")
            throw APIError.serverError(statusCode: code, detail: errorBody)
        }
    }

    // MARK: - Alerts

    func fetchAlerts(unreadOnly: Bool = false) async throws -> BackendAlertList {
        let path = unreadOnly ? "alerts?unread_only=true" : "alerts"
        return try await get(path)
    }

    func markAlertRead(alertId: Int) async throws {
        try await patchEmpty("alerts/\(alertId)/read")
    }

    func markAllAlertsRead() async throws {
        let url = baseURL.appendingPathComponent("alerts/read-all")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
    }

    func triggerAlertScan() async throws {
        let url = baseURL.appendingPathComponent("alerts/scan")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
    }

    // MARK: - SSE stream (POST /chat/stream)

    nonisolated func chatStream(
        message: String,
        sessionId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        let devId = deviceId
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = await baseURL.appendingPathComponent("chat/stream")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(devId, forHTTPHeaderField: "X-Device-Id")
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

// MARK: - Portfolio & Transaction DTOs

struct BackendPosition: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let shares: Double
    let avgBuyPrice: Double
    let totalCost: Double
    let currentPrice: Double
    let currentValue: Double
    let pnl: Double
    let pnlPct: Double

    enum CodingKeys: String, CodingKey {
        case ticker, name, shares
        case avgBuyPrice = "avg_buy_price"
        case totalCost = "total_cost"
        case currentPrice = "current_price"
        case currentValue = "current_value"
        case pnl
        case pnlPct = "pnl_pct"
    }
}

struct BackendPortfolioSummary: Codable, Sendable {
    let totalCost: Double
    let currentValue: Double
    let pnl: Double
    let pnlPct: Double
    let positions: [BackendPosition]

    enum CodingKeys: String, CodingKey {
        case totalCost = "total_cost"
        case currentValue = "current_value"
        case pnl
        case pnlPct = "pnl_pct"
        case positions
    }
}

struct BackendHoldingLot: Codable, Identifiable, Sendable {
    let id: String
    let ticker: String
    let stockName: String?
    let shares: Double
    let pricePerShare: Double
    let totalInvested: Double
    let buyDate: String

    enum CodingKeys: String, CodingKey {
        case id, ticker
        case stockName = "stock_name"
        case shares
        case pricePerShare = "price_per_share"
        case totalInvested = "total_invested"
        case buyDate = "buy_date"
    }
}

struct BackendHoldingLotList: Codable, Sendable {
    let lots: [BackendHoldingLot]
}

struct BackendHoldingLotIn: Codable, Sendable {
    let id: String?
    let ticker: String
    let pricePerShare: Double
    let shares: Double?
    let totalInvested: Double?
    let buyDate: String?

    enum CodingKeys: String, CodingKey {
        case id, ticker
        case pricePerShare = "price_per_share"
        case shares
        case totalInvested = "total_invested"
        case buyDate = "buy_date"
    }
}

struct BackendSellIn: Codable, Sendable {
    let ticker: String
    let shares: Double
    let sellPrice: Double

    enum CodingKeys: String, CodingKey {
        case ticker, shares
        case sellPrice = "sell_price"
    }
}

struct BackendSellResult: Codable, Sendable {
    let ticker: String
    let soldShares: Double
    let realizedPnl: Double
    let remainingShares: Double

    enum CodingKeys: String, CodingKey {
        case ticker
        case soldShares = "sold_shares"
        case realizedPnl = "realized_pnl"
        case remainingShares = "remaining_shares"
    }
}

// MARK: - Recommendations DTOs

struct BackendScoreBreakdown: Codable, Sendable {
    let fundamental: Double
    let macro: Double
    let sector: Double
    let risk: Double
    let sentiment: Double
}

struct BackendRecommendation: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let overallScore: Double
    let recommendation: String
    let reasoning: String
    let scores: BackendScoreBreakdown
    let scoredAt: String

    enum CodingKeys: String, CodingKey {
        case ticker, name
        case overallScore = "overall_score"
        case recommendation, reasoning, scores
        case scoredAt = "scored_at"
    }
}

struct BackendRecommendationList: Codable, Sendable {
    let scoredAt: String?
    let recommendations: [BackendRecommendation]

    enum CodingKeys: String, CodingKey {
        case scoredAt = "scored_at"
        case recommendations
    }
}

// MARK: - Alerts DTOs

struct BackendAlert: Codable, Identifiable, Sendable {
    let id: Int
    let ticker: String?
    let alertType: String
    let severity: String
    let message: String
    let isRead: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, ticker
        case alertType = "alert_type"
        case severity, message
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

struct BackendAlertList: Codable, Sendable {
    let unreadCount: Int
    let alerts: [BackendAlert]

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case alerts
    }
}

// MARK: - Market Intelligence DTOs

struct BackendInsightChip: Codable, Sendable {
    let label: String
    let text: String
}

struct BackendMarketIntelligence: Codable, Sendable {
    let generatedDate: String
    let insights: [BackendInsightChip]

    enum CodingKeys: String, CodingKey {
        case generatedDate = "generated_date"
        case insights
    }
}

struct BackendStockInsights: Codable, Sendable {
    let ticker: String
    let generatedDate: String
    let insights: [BackendInsightChip]

    enum CodingKeys: String, CodingKey {
        case ticker
        case generatedDate = "generated_date"
        case insights
    }
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case requestFailed
    case decodingFailed
    case serverError(statusCode: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Request failed"
        case .decodingFailed: "Failed to decode response"
        case .serverError(let code, let detail): "Server error (\(code)): \(detail)"
        }
    }
}
