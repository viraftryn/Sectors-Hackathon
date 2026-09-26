import Foundation

// MARK: - Legacy Stock Model
struct Stock: Codable, Identifiable {
    let ticker: String
    let name: String
    let price: Double
    let change: Double

    var id: String { ticker }
}

// MARK: - Sectors API Response Models (v2 Schema)

struct SectorsCompanyReportResponse: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let companyName: String
    let market: String?
    let overview: SectorsOverview
    let valuation: SectorsValuation?
    let future: SectorsFuture?
    let financials: SectorsFinancials?
    let dividend: SectorsDividend?
    let dailyPrices: [SectorsDailyPrice]?

    enum CodingKeys: String, CodingKey {
        case symbol
        case companyName = "company_name"
        case market
        case overview
        case valuation
        case future
        case financials
        case dividend
        case dailyPrices = "daily_prices"
    }
}

struct SectorsOverview: Codable {
    let listingBoard: String?
    let industry: String?
    let subIndustry: String?
    let sector: String?
    let subSector: String?
    let marketCap: Double?
    let marketCapRank: Int?
    let lastClosePrice: Double
    let latestCloseDate: String?
    let dailyCloseChange: Double
    let priceChange: Double?

    enum CodingKeys: String, CodingKey {
        case listingBoard = "listing_board"
        case industry
        case subIndustry = "sub_industry"
        case sector
        case subSector = "sub_sector"
        case marketCap = "market_cap"
        case marketCapRank = "market_cap_rank"
        case lastClosePrice = "last_close_price"
        case latestCloseDate = "latest_close_date"
        case dailyCloseChange = "daily_close_change"
        case priceChange = "price_change"
    }
}

struct SectorsValuation: Codable {
    let lastClosePrice: Double?
    let forwardPe: Double?
    let intrinsicValue: Double?

    enum CodingKeys: String, CodingKey {
        case lastClosePrice = "last_close_price"
        case forwardPe = "forward_pe"
        case intrinsicValue = "intrinsic_value"
    }
}

struct SectorsFuture: Codable {
    let analystRatingBreakdown: SectorsAnalystRatingBreakdown?

    enum CodingKeys: String, CodingKey {
        case analystRatingBreakdown = "analyst_rating_breakdown"
    }
}

struct SectorsAnalystRatingBreakdown: Codable {
    let strongBuy: Int?
    let buy: Int?
    let hold: Int?
    let sell: Int?
    let strongSell: Int?
    let nAnalyst: Int?

    enum CodingKeys: String, CodingKey {
        case strongBuy = "strong_buy"
        case buy
        case hold
        case sell
        case strongSell = "strong_sell"
        case nAnalyst = "n_analyst"
    }
}

struct SectorsFinancials: Codable {
    let eps: Double?
}

struct SectorsDividend: Codable {
    let yieldTtm: Double?
    let dividendTtm: Double?
    let payoutRatio: Double?

    enum CodingKeys: String, CodingKey {
        case yieldTtm = "yield_ttm"
        case dividendTtm = "dividend_ttm"
        case payoutRatio = "payout_ratio"
    }
}

struct SectorsDailyPrice: Codable {
    let date: String
    let close: Double
    let volume: Double?
}

// MARK: - Sectors Stocks Loader

enum SectorsStocksLoader {
    static func loadRawReports() -> [SectorsCompanyReportResponse] {
        // 1. Coba dari Bundle.main
        if let url = Bundle.main.url(forResource: "sectors_stocks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let reports = try? JSONDecoder().decode([SectorsCompanyReportResponse].self, from: data) {
            return reports
        }

        // 2. Coba dari path lokal project jika dalam development/simulator
        let localPath = "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Resources/sectors_stocks.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
           let reports = try? JSONDecoder().decode([SectorsCompanyReportResponse].self, from: data) {
            return reports
        }

        return []
    }

    static func loadStockItems() -> [StockItem] {
        let reports = loadRawReports()
        guard !reports.isEmpty else {
            return []
        }

        return reports.map { report in
            report.toStockItem()
        }
    }
}

extension SectorsCompanyReportResponse {
    func toStockItem() -> StockItem {
        // Clean symbol: e.g. "BBCA.JK" -> "BBCA"
        let cleanSymbol = symbol.components(separatedBy: ".").first ?? symbol

        // Market detection
        let detectedMarket = self.market ?? "IDX"

        // Clean company name
        let cleanName = companyName
            .replacingOccurrences(of: "PT ", with: "")
            .replacingOccurrences(of: " Tbk.", with: "")
            .replacingOccurrences(of: " (Persero)", with: "")
            .trimmingCharacters(in: .whitespaces)

        let price = overview.lastClosePrice
        let pctChange = overview.dailyCloseChange * 100.0
        let change = overview.priceChange ?? (price * overview.dailyCloseChange)

        // Hitung sentimen dari data Sectors analystRatingBreakdown
        let sentiment: Sentiment
        if let ratings = future?.analystRatingBreakdown, let total = ratings.nAnalyst, total > 0 {
            let strongBuy = Double(ratings.strongBuy ?? 0)
            let buyCount = Double(ratings.buy ?? 0)
            let holdCount = Double(ratings.hold ?? 0)
            let sellCount = Double(ratings.sell ?? 0)
            let strongSell = Double(ratings.strongSell ?? 0)

            let buyRatio = (strongBuy + buyCount) / Double(total)
            let holdRatio = holdCount / Double(total)
            let sellRatio = (sellCount + strongSell) / Double(total)
            let score = round(buyRatio * 100.0)

            sentiment = Sentiment(
                buy: buyRatio,
                hold: holdRatio,
                sell: sellRatio,
                score: score
            )
        } else {
            sentiment = Sentiment(buy: 0.5, hold: 0.3, sell: 0.2, score: 60)
        }

        // Hitung normalisasi sparkData (0.0 - 1.0) dari daily_prices Sectors API
        var spark: [Double] = []
        if let daily = dailyPrices, daily.count > 1 {
            let closes = daily.map { $0.close }
            let minVal = closes.min() ?? 0
            let maxVal = closes.max() ?? 1
            let diff = maxVal - minVal
            if diff > 0 {
                spark = closes.map { ($0 - minVal) / diff }
            } else {
                spark = Array(repeating: 0.5, count: closes.count)
            }
        } else {
            spark = [0.3, 0.4, 0.45, 0.5, 0.55, 0.6]
        }

        return StockItem(
            symbol: cleanSymbol,
            name: cleanName,
            sector: overview.sector ?? overview.industry ?? "General",
            price: price,
            change: change,
            percentChange: pctChange,
            sentiment: sentiment,
            market: detectedMarket,
            sparkData: spark
        )
    }
}

// MARK: - ==========================================
// MARK: - Backend FastAPI Schema Models (v2)
// MARK: - ==========================================

struct BackendStockSummary: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let sector: String
    let subSector: String
    let price: Double
    let changePct: Double?
    let marketCap: Double?

    enum CodingKeys: String, CodingKey {
        case ticker
        case name
        case sector
        case subSector = "sub_sector"
        case price
        case changePct = "change_pct"
        case marketCap = "market_cap"
    }

    func toStockItem() -> StockItem {
        let pct = changePct ?? 0.0
        let chg = price * (pct / 100.0)
        let cleanName = name
            .replacingOccurrences(of: "PT ", with: "")
            .replacingOccurrences(of: " Tbk.", with: "")
            .replacingOccurrences(of: " Tbk", with: "")
            .replacingOccurrences(of: " (Persero)", with: "")
            .trimmingCharacters(in: .whitespaces)

        return StockItem(
            symbol: ticker,
            name: cleanName,
            sector: sector,
            price: price,
            change: chg,
            percentChange: pct,
            sentiment: Sentiment(buy: 0.65, hold: 0.25, sell: 0.10, score: 75),
            market: "IDX",
            sparkData: [0.35, 0.40, 0.38, 0.45, 0.50, 0.55, 0.52, 0.58, 0.62, 0.65]
        )
    }
}

struct BackendStockListResponse: Codable, Sendable {
    let stocks: [BackendStockSummary]
}

struct BackendFundamentals: Codable, Sendable {
    let pe: Double?
    let pb: Double?
    let roePct: Double?
    let der: Double?
    let dividendYieldPct: Double?

    enum CodingKeys: String, CodingKey {
        case pe
        case pb
        case roePct = "roe_pct"
        case der
        case dividendYieldPct = "dividend_yield_pct"
    }
}

struct BackendPricePoint: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double
    let volume: Int?
}

struct BackendStockDetail: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let sector: String
    let subSector: String
    let price: Double
    let changePct: Double?
    let marketCap: Double?
    let fundamentals: BackendFundamentals
    let week52High: Double?
    let week52Low: Double?
    let prices: [BackendPricePoint]
    let insights: [BackendInsightChip]?

    enum CodingKeys: String, CodingKey {
        case ticker
        case name
        case sector
        case subSector = "sub_sector"
        case price
        case changePct = "change_pct"
        case marketCap = "market_cap"
        case fundamentals
        case week52High = "week52_high"
        case week52Low = "week52_low"
        case prices
        case insights
    }

    func toStockQuote() -> StockQuote {
        let pct = changePct ?? 0.0
        let chg = price * (pct / 100.0)
        let prev = price - chg
        return StockQuote(
            ticker: ticker,
            name: name,
            price: price,
            change: chg,
            changePercent: pct,
            previousClose: prev,
            currency: "IDR"
        )
    }

    func toStockFundamentals() -> StockFundamentals {
        StockFundamentals(
            ticker: ticker,
            pe: fundamentals.pe,
            pb: fundamentals.pb,
            roe: fundamentals.roePct,
            der: fundamentals.der,
            dividendYield: fundamentals.dividendYieldPct,
            week52High: week52High,
            week52Low: week52Low,
            sector: sector
        )
    }

    func toHistoryPoints() -> [StockHistoryPoint] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current

        return prices.compactMap { p in
            guard let rawDate = dateFormatter.date(from: p.date) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: rawDate)
            comps.hour = 16
            comps.minute = 0
            comps.second = 0
            let d = calendar.date(from: comps) ?? rawDate
            guard !calendar.isDateInWeekend(d) else { return nil }
            return StockHistoryPoint(
                date: d,
                price: p.close,
                volume: p.volume ?? 0
            )
        }
    }
}

struct BackendMarketOverview: Codable, Sendable {
    let ihsg: BackendIndexSummary
    let foreignFlow: BackendForeignFlow?
    let topGainers: [BackendMover]
    let topLosers: [BackendMover]
    let mostTraded: [BackendTradedStock]

    enum CodingKeys: String, CodingKey {
        case ihsg
        case foreignFlow = "foreign_flow"
        case topGainers = "top_gainers"
        case topLosers = "top_losers"
        case mostTraded = "most_traded"
    }
}

struct BackendIndexSummary: Codable, Sendable {
    let name: String
    let value: Double
    let changePct: Double?
    let date: String
    let series: [BackendIndexPoint]

    enum CodingKeys: String, CodingKey {
        case name, value
        case changePct = "change_pct"
        case date, series
    }
}

struct BackendIndexPoint: Codable, Sendable {
    let date: String
    let value: Double
}

struct BackendForeignFlow: Codable, Sendable {
    let date: String
    let netForeignInflow: Double

    enum CodingKeys: String, CodingKey {
        case date
        case netForeignInflow = "net_foreign_inflow"
    }
}

struct BackendMover: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let price: Double
    let changePct: Double

    enum CodingKeys: String, CodingKey {
        case ticker, name, price
        case changePct = "change_pct"
    }
}

struct BackendTradedStock: Codable, Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let volume: Int
    let price: Double
}

