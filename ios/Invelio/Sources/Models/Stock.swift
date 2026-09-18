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
        // Clean symbol: e.g. "BBCA.JK" -> "BBCA", "D05.SI" -> "D05"
        let cleanSymbol = symbol.components(separatedBy: ".").first ?? symbol

        // Market detection
        let detectedMarket: String
        if let m = self.market {
            detectedMarket = m
        } else if symbol.hasSuffix(".JK") {
            detectedMarket = "IDX"
        } else if symbol.hasSuffix(".SI") {
            detectedMarket = "SGX"
        } else if symbol.hasSuffix(".KL") {
            detectedMarket = "KLSE"
        } else {
            detectedMarket = "IDX"
        }

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
