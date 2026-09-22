import SwiftUI
import SwiftData

// MARK: - Lightweight Sendable Holding DTO
struct HoldingSummaryItem: Sendable {
    let ticker: String
    let stockName: String
    let shares: Double
    let pricePerShare: Double
    let totalInvested: Double
    let currency: String
}

// MARK: - Message Model
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - View Model
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isProcessing: Bool = false

    func send(_ query: String, holdings: [HoldingSummaryItem] = []) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }

        // Tambahkan pesan user
        let userMessage = ChatMessage(text: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        // Placeholder respon bot
        let botMessageId = UUID()
        let placeholderBotMessage = ChatMessage(
            id: botMessageId,
            text: "",
            isUser: false,
            timestamp: Date()
        )
        messages.append(placeholderBotMessage)

        // Asynchronous AI & Sectors API analysis
        Task {
            let answer = await generateAIAnswer(for: trimmed, holdings: holdings)
            finalizeBotResponse(messageId: botMessageId, text: answer)
            isProcessing = false
        }
    }

    private func finalizeBotResponse(messageId: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index] = ChatMessage(
            id: messageId,
            text: text,
            isUser: false,
            timestamp: Date()
        )
    }

    func resetSession() {
        messages.removeAll()
        inputText = ""
        isProcessing = false
    }

    // MARK: - Context-Aware Sectors & Portfolio AI Analysis Engine

    private func generateAIAnswer(for query: String, holdings: [HoldingSummaryItem]) async -> String {
        let q = query.uppercased()

        // 1. User Portfolio / Holdings Analysis
        if q.contains("PORTFOLIO") || q.contains("MY STOCK") || q.contains("HOLDING") ||
           q.contains("UNTUNG") || q.contains("RUGI") || q.contains("PNL") ||
           q.contains("SAHAM SAYA") || q.contains("INVESTASI SAYA") || q.contains("POSISI SAYA") {
            return await generatePortfolioAnalysis(holdings: holdings)
        }

        // 2. Specific Stock Fundamental Analysis via Sectors API
        let knownTickers = [
            "BBCA", "BBRI", "BMRI", "BBNI", "TLKM", "ASII", "GOTO", "AMMN", "BREN",
            "ADRO", "ICBP", "INDF", "UNVR", "KLBF", "CPIN", "SMGR", "BRPT", "PTBA",
            "ITMG", "PGAS", "MDKA", "TPIA", "MEDC", "INKP", "ANTM", "ISAT", "EXCL"
        ]

        var detectedTicker: String? = nil
        for t in knownTickers {
            if q.contains(t) {
                detectedTicker = t
                break
            }
        }

        if detectedTicker == nil {
            let words = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for word in words {
                let upper = word.uppercased()
                if upper.count == 4 && upper.allSatisfy({ $0.isLetter }) {
                    detectedTicker = upper
                    break
                }
            }
        }

        if let ticker = detectedTicker {
            return await generateStockAnalysis(ticker: ticker, userHoldings: holdings)
        }

        // 3. Dividend Analysis
        if q.contains("DIVIDEN") || q.contains("DIVIDEND") || q.contains("YIELD") {
            return await generateDividendAnalysis()
        }

        // 4. Market Movers & Macro Outlook
        if q.contains("MARKET") || q.contains("IHSG") || q.contains("OUTLOOK") || q.contains("MOVERS") || q.contains("TREND") {
            return await generateMarketOverviewAnalysis()
        }

        // 5. Stock Recommendations
        if q.contains("RECOMMEND") || q.contains("REKOMENDASI") || q.contains("TOP PICK") {
            return """
            **Recommended Sectors Stocks (Institutional Picks)**

            1. **BBCA (PT Bank Central Asia Tbk)**
               • **Thesis:** Highest CASA ratio (>80%), industry-leading ROE (~22%), stellar asset quality with NPL below 2%.
               • **Action:** Long-term core holding / Buy on dips.

            2. **BMRI (PT Bank Mandiri Tbk)**
               • **Thesis:** High digital banking operational leverage (Livin' by Mandiri) and attractive dividend yield (>5%).
               • **Action:** Accumulate for dividend growth and earnings stability.

            3. **TLKM (PT Telkom Indonesia Tbk)**
               • **Thesis:** FMC synergy unlocking value, dominant mobile market share, and data center growth (NeutraDC).
               • **Action:** Defensive value buy with solid ~4.5% yield.

            💡 *Tip: Ask "Analysis BBCA" or "Portfolio" to get real-time valuation metrics!*
            """
        }

        // 6. Default Fallback
        return """
        **Invelio Financial AI Assistant**

        I'm ready to assist with real-time Indonesian equity insights powered by Sectors API v2:

        • **Portfolio Analysis:** Ask *"How is my portfolio performing?"* or *"Portfolio risk"* to analyze your active holdings.
        • **Stock Fundamentals:** Ask *"Analysis BBCA"*, *"TLKM valuation"*, or *"How is ASII?"* to see live P/E, PBV, ROE, DER, and 52W range.
        • **Dividends:** Ask *"Top dividend stocks"* to explore high-yield dividend champions.
        • **Market Macro:** Ask *"Market overview"* or *"IHSG outlook"*.
        """
    }

    private func generatePortfolioAnalysis(holdings: [HoldingSummaryItem]) async -> String {
        if holdings.isEmpty {
            return """
            **Portfolio Status: No Active Holdings**

            You haven't added any stocks to your Invelio portfolio yet.

            💡 **How to track your portfolio:**
            1. Go to the **Home** tab and pick any Indonesian stock.
            2. Tap **Add / Manage Lots** in the Stock Detail page.
            3. Enter your purchase price and total invested amount.
            4. Your holdings will automatically sync to Supabase, and I can provide personalized risk & performance insights!
            """
        }

        let grouped = Dictionary(grouping: holdings, by: { $0.ticker })
        let pgStocks = await SupabaseService.shared.fetchStocks()
        let liveSummaries = (try? await APIClient.shared.fetchStocks()) ?? []

        var totalCost: Double = 0
        var totalMarketValue: Double = 0
        var positionLines: [String] = []

        for (ticker, lots) in grouped {
            let shares = lots.reduce(0.0) { $0 + $1.shares }
            let invested = lots.reduce(0.0) { $0 + $1.totalInvested }
            let avgCost = shares > 0 ? (invested / shares) : 0

            let pgMatched = pgStocks.first { $0.ticker.uppercased().hasPrefix(ticker.uppercased()) }
            let matched = liveSummaries.first { $0.ticker.uppercased().hasPrefix(ticker.uppercased()) }
            let currentPrice = pgMatched?.price ?? (matched?.price ?? (lots.first?.pricePerShare ?? 0))
            let mVal = shares * currentPrice
            let pnl = mVal - invested
            let pnlPct = invested > 0 ? (pnl / invested) * 100.0 : 0.0

            totalCost += invested
            totalMarketValue += mVal

            let sign = pnl >= 0 ? "+" : ""
            positionLines.append("• **\(ticker)**: \(Int(shares)) shares | Avg: Rp \(Int(avgCost)) | Value: Rp \(StockFormatters.stockPrice(mVal, currency: "IDR")) (\(sign)\(String(format: "%.1f", pnlPct))%)")
        }

        let totalPnL = totalMarketValue - totalCost
        let totalPnLPct = totalCost > 0 ? (totalPnL / totalCost) * 100.0 : 0.0
        let pnlSign = totalPnL >= 0 ? "+" : ""
        let statusEmoji = totalPnL >= 0 ? "🟢" : "🔴"

        var riskNote = ""
        if grouped.count == 1 {
            riskNote = "⚠️ **High Concentration Alert**: 100% of your portfolio is in a single stock. Consider diversifying into defensive consumer or banking sectors."
        } else if grouped.count <= 3 {
            riskNote = "ℹ️ **Moderate Diversification**: Holding \(grouped.count) stocks. Ensure your allocation isn't overweighted (>40%) in a single cyclical name."
        } else {
            riskNote = "✅ **Healthy Diversification**: Holding \(grouped.count) different stocks across sectors."
        }

        return """
        **Your Portfolio Analysis** \(statusEmoji)

        • **Total Value:** Rp \(StockFormatters.stockPrice(totalMarketValue, currency: "IDR"))
        • **Total Invested:** Rp \(StockFormatters.stockPrice(totalCost, currency: "IDR"))
        • **Unrealized P&L:** \(pnlSign)Rp \(StockFormatters.stockPrice(abs(totalPnL), currency: "IDR")) (\(pnlSign)\(String(format: "%.2f", totalPnLPct))%)

        **Current Holdings Breakdown:**
        \(positionLines.joined(separator: "\n"))

        **Risk Assessment:**
        \(riskNote)

        💡 *Tip: You can ask for a deep dive on any of your holdings by asking "Analysis \(grouped.keys.first ?? "BBCA")".*
        """
    }

    private func generateStockAnalysis(ticker: String, userHoldings: [HoldingSummaryItem]) async -> String {
        // 1. Direct from Supabase PostgreSQL (0 Credit!)
        if let pg = await SupabaseService.shared.fetchStockDetail(ticker: ticker) {
            let cleanTicker = pg.ticker.components(separatedBy: ".").first ?? pg.ticker
            let userLots = userHoldings.filter { $0.ticker.uppercased().hasPrefix(cleanTicker.uppercased()) }
            var userPositionText = ""
            if !userLots.isEmpty {
                let shares = userLots.reduce(0.0) { $0 + $1.shares }
                let invested = userLots.reduce(0.0) { $0 + $1.totalInvested }
                let avg = shares > 0 ? (invested / shares) : 0
                let curVal = shares * pg.price
                let pnl = curVal - invested
                let sign = pnl >= 0 ? "+" : ""
                userPositionText = "\n📌 **Your Position:** \(Int(shares)) shares @ Avg Rp \(Int(avg)) | Value: Rp \(StockFormatters.stockPrice(curVal, currency: "IDR")) (\(sign)Rp \(StockFormatters.stockPrice(abs(pnl), currency: "IDR")))\n"
            }

            var commentary: [String] = []
            if let pe = pg.pe_ttm {
                if pe < 10 {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Highly attractive valuation below IDX peer average.")
                } else if pe < 18 {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Fair valuation reflecting steady institutional demand.")
                } else {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Trading at a premium growth valuation.")
                }
            }

            if let roe = pg.roe_ttm {
                if roe >= 15.0 {
                    commentary.append("• **ROE (\(String(format: "%.1f", roe))%):** Excellent profitability and high capital efficiency (above 15% benchmark).")
                } else {
                    commentary.append("• **ROE (\(String(format: "%.1f", roe))%):** Moderate return on equity.")
                }
            }

            if let yield = pg.yield_ttm, yield > 0 {
                commentary.append("• **Dividend Yield (\(String(format: "%.1f", yield))%):** Strong defensive income stream.")
            }

            if let der = pg.der_mrq {
                if der < 1.0 {
                    commentary.append("• **DER (\(String(format: "%.2f", der))x):** Conservative debt profile with robust solvency cushion.")
                }
            }

            let changeSign = (pg.change_pct ?? 0) >= 0 ? "+" : ""
            let changeText = String(format: "%@%.2f%%", changeSign, pg.change_pct ?? 0)

            return """
            **Analysis: \(pg.name) (\(cleanTicker))**
            Sector: \(pg.sector ?? "IDX") • Sub-Sector: \(pg.sub_sector ?? "")

            • **Latest Price:** Rp \(StockFormatters.stockPrice(pg.price, currency: "IDR")) (\(changeText))
            • **52-Week Range:** Rp \(pg.week52_low != nil ? StockFormatters.stockPrice(pg.week52_low!, currency: "IDR") : "-") — Rp \(pg.week52_high != nil ? StockFormatters.stockPrice(pg.week52_high!, currency: "IDR") : "-")\(userPositionText)
            **Fundamental Metrics (Sectors API v2 / PostgreSQL):**
            • **P/E (TTM):** \(pg.pe_ttm != nil ? String(format: "%.1fx", pg.pe_ttm!) : "N/A")
            • **PBV (MRQ):** \(pg.pb_mrq != nil ? String(format: "%.2fx", pg.pb_mrq!) : "N/A")
            • **ROE (TTM):** \(pg.roe_ttm != nil ? String(format: "%.1f%%", pg.roe_ttm!) : "N/A")
            • **Div Yield:** \(pg.yield_ttm != nil ? String(format: "%.1f%%", pg.yield_ttm!) : "N/A")
            • **DER:** \(pg.der_mrq != nil ? String(format: "%.2fx", pg.der_mrq!) : "N/A")

            **Institutional Assessment:**
            \(commentary.joined(separator: "\n"))
            """
        }
        do {
            let detail = try await APIClient.shared.fetchStockDetail(ticker: ticker)
            let f = detail.fundamentals
            let cleanTicker = detail.ticker.components(separatedBy: ".").first ?? detail.ticker

            let userLots = userHoldings.filter { $0.ticker.uppercased().hasPrefix(cleanTicker.uppercased()) }
            var userPositionText = ""
            if !userLots.isEmpty {
                let shares = userLots.reduce(0.0) { $0 + $1.shares }
                let invested = userLots.reduce(0.0) { $0 + $1.totalInvested }
                let avg = shares > 0 ? (invested / shares) : 0
                let curVal = shares * detail.price
                let pnl = curVal - invested
                let sign = pnl >= 0 ? "+" : ""
                userPositionText = "\n📌 **Your Position:** \(Int(shares)) shares @ Avg Rp \(Int(avg)) | Value: Rp \(StockFormatters.stockPrice(curVal, currency: "IDR")) (\(sign)Rp \(StockFormatters.stockPrice(abs(pnl), currency: "IDR")))\n"
            }

            var commentary: [String] = []
            if let pe = f.pe {
                if pe < 12 {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Trades at an attractive discount compared to the IDX historical average (~14x).")
                } else if pe < 20 {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Fairly valued reflecting solid earnings consistency.")
                } else {
                    commentary.append("• **P/E Ratio (\(String(format: "%.1f", pe))x):** Growth premium reflected in current valuation.")
                }
            }

            if let roe = f.roePct {
                if roe >= 15.0 {
                    commentary.append("• **ROE (\(String(format: "%.1f", roe))%):** Excellent profitability and capital efficiency (well above 15% benchmark).")
                } else {
                    commentary.append("• **ROE (\(String(format: "%.1f", roe))%):** Moderate return on equity.")
                }
            }

            if let yield = f.dividendYieldPct, yield > 0 {
                commentary.append("• **Dividend Yield (\(String(format: "%.1f", yield))%):** Provides defensive dividend income.")
            }

            if let der = f.der {
                if der < 1.0 {
                    commentary.append("• **DER (\(String(format: "%.2f", der))x):** Conservative debt profile with strong solvency headroom.")
                }
            }

            let changeSign = (detail.changePct ?? 0) >= 0 ? "+" : ""
            let changeText = String(format: "%@%.2f%%", changeSign, detail.changePct ?? 0)

            return """
            **Analysis: \(detail.name) (\(cleanTicker))**
            Sector: \(detail.sector) • Sub-Sector: \(detail.subSector)

            • **Latest Price:** Rp \(StockFormatters.stockPrice(detail.price, currency: "IDR")) (\(changeText))
            • **52-Week Range:** Rp \(detail.week52Low != nil ? StockFormatters.stockPrice(detail.week52Low!, currency: "IDR") : "-") — Rp \(detail.week52High != nil ? StockFormatters.stockPrice(detail.week52High!, currency: "IDR") : "-")\(userPositionText)
            **Fundamental Metrics (Sectors API v2):**
            • **P/E (TTM):** \(f.pe != nil ? String(format: "%.1fx", f.pe!) : "N/A")
            • **PBV (MRQ):** \(f.pb != nil ? String(format: "%.2fx", f.pb!) : "N/A")
            • **ROE (TTM):** \(f.roePct != nil ? String(format: "%.1f%%", f.roePct!) : "N/A")
            • **Div Yield:** \(f.dividendYieldPct != nil ? String(format: "%.1f%%", f.dividendYieldPct!) : "N/A")
            • **DER:** \(f.der != nil ? String(format: "%.2fx", f.der!) : "N/A")

            **Institutional Assessment:**
            \(commentary.joined(separator: "\n"))
            """
        } catch {
            return """
            **Stock Analysis: \(ticker)**

            Unable to reach live Sectors API v2 server for \(ticker) right now.

            **General Guidelines:**
            • Check the **Home** tab or company details to review historical price charts and reports.
            • Ensure your backend API server is running (`http://localhost:8000`).
            """
        }
    }

    private func generateDividendAnalysis() async -> String {
        // 1. Prioritize live data from Supabase PostgreSQL (0 Credit!)
        let pgStocks = await SupabaseService.shared.fetchStocks()
        let pgSorted = pgStocks
            .compactMap { s -> (String, String, Double, Double)? in
                guard let y = s.yield_ttm, y > 0 else { return nil }
                return (s.symbol, s.name, y, s.price)
            }
            .sorted { $0.2 > $1.2 }

        if !pgSorted.isEmpty {
            var lines: [String] = []
            for item in pgSorted.prefix(5) {
                let cleanName = item.1
                    .replacingOccurrences(of: "PT ", with: "")
                    .replacingOccurrences(of: " Tbk.", with: "")
                    .replacingOccurrences(of: " Tbk", with: "")
                    .replacingOccurrences(of: " (Persero)", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let yieldPct = item.2 > 1.0 ? item.2 : (item.2 * 100.0)
                lines.append("• **\(item.0)** (\(cleanName)): **\(String(format: "%.2f%%", yieldPct))** Yield | Price: Rp \(StockFormatters.stockPrice(item.3, currency: "IDR"))")
            }
            return """
            **Top Dividend Yield Stocks on IDX (PostgreSQL Database)**

            \(lines.joined(separator: "\n"))

            💡 *Strategy Tip: Combine high dividend yield (>6%) with low Debt-to-Equity (<1.0x) to ensure dividend sustainability across economic cycles.*
            """
        }

        let reports = SectorsStocksLoader.loadRawReports()
        let sorted = reports
            .compactMap { r -> (String, String, Double, Double)? in
                guard let y = r.dividend?.yieldTtm, y > 0 else { return nil }
                return (r.symbol, r.companyName, y, r.overview.lastClosePrice)
            }
            .sorted { $0.2 > $1.2 }

        if !sorted.isEmpty {
            var lines: [String] = []
            for item in sorted.prefix(5) {
                let clean = item.0.components(separatedBy: ".").first ?? item.0
                let yieldPct = item.2 > 1.0 ? item.2 : (item.2 * 100.0)
                lines.append("• **\(clean)** (\(item.1)): **\(String(format: "%.1f%%", yieldPct))** Yield | Price: Rp \(StockFormatters.stockPrice(item.3, currency: "IDR"))")
            }
            return """
            **Top Dividend Yield Stocks on IDX (PostgreSQL Database)**

            \(lines.joined(separator: "\n"))

            💡 *Strategy Tip: Combine high dividend yield (>6%) with low Debt-to-Equity (<1.0x) to ensure dividend sustainability across economic cycles.*
            """
        }

        return """
        **Top High Dividend Yield Stocks on IDX**

        1. **PTBA (Bukit Asam)** — Est. Yield ~11.5% | Payout Ratio ~75%
        2. **ITMG (Indo Tambangraya)** — Est. Yield ~12.0% | Payout Ratio ~65%
        3. **ASII (Astra International)** — Est. Yield ~7.8% | Payout Ratio ~50%
        4. **BMRI (Bank Mandiri)** — Est. Yield ~5.2% | Consistent annual dividend growth
        5. **BBRI (Bank Rakyat Indonesia)** — Est. Yield ~5.5% | High payout dividend champion

        💡 *Tip: Track ex-dividend dates carefully and ensure cash flows cover capital expenditures.*
        """
    }

    private func generateMarketOverviewAnalysis() async -> String {
        do {
            let overview = try await APIClient.shared.fetchMarketOverview()
            let ihsg = overview.ihsg
            let sign = (ihsg.changePct ?? 0) >= 0 ? "+" : ""
            let pctText = String(format: "%@%.2f%%", sign, ihsg.changePct ?? 0)

            var flowText = ""
            if let f = overview.foreignFlow {
                let flowInBillion = f.netForeignInflow / 1_000_000_000.0
                let flowSign = flowInBillion >= 0 ? "Net Buy" : "Net Sell"
                flowText = "• **Foreign Flow:** \(flowSign) Rp \(String(format: "%.1f", abs(flowInBillion))) Billion"
            }

            var gainerLines: [String] = []
            for g in overview.topGainers.prefix(3) {
                gainerLines.append("\(g.ticker) (+\(String(format: "%.1f", g.changePct))%)")
            }

            return """
            **IDX Market Overview (Sectors API v2)**

            • **IHSG (Composite Index):** \(String(format: "%.2f", ihsg.value)) (\(pctText))
            \(flowText.isEmpty ? "" : "\(flowText)\n")• **Top Gainers:** \(gainerLines.joined(separator: ", "))

            **Macro Sentiment:**
            Domestic macroeconomic indicators remain resilient with stable inflation and healthy banking liquidity supporting IDX valuations.
            """
        } catch {
            return """
            **IDX Market Summary**

            • **Overall Trend:** IDX Composite consolidates with active rotation into banking and defensive consumer names.
            • **Foreign Flow:** Sustained selective net foreign accumulation on big-cap banks.
            • **Key Catalyst:** Bank Indonesia interest rate stability and earnings performance.
            """
        }
    }
}

// MARK: - Chat Bubble Row
struct ChatBubbleRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 44)
                userBubble
            } else {
                botBubble
                Spacer(minLength: 44)
            }
        }
    }

    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 65/255, green: 55/255, blue: 135/255),
                                Color(red: 45/255, green: 38/255, blue: 95/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }

    private var botBubble: some View {
        Group {
            if message.text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Analyzing...")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.AICardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
            } else {
                Text(LocalizedStringKey(message.text))
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.AICardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
            }
        }
    }
}

// MARK: - Main Chatbot View
struct ChatbotView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Query private var holdingLots: [HoldingLot]
    @FocusState private var isInputFocused: Bool

    private var holdingSummaries: [HoldingSummaryItem] {
        holdingLots.map {
            HoldingSummaryItem(
                ticker: $0.ticker,
                stockName: $0.stockName,
                shares: $0.shares,
                pricePerShare: $0.pricePerShare,
                totalInvested: $0.totalInvested,
                currency: $0.currency
            )
        }
    }

    private let sampleSuggestions = [
        "My Stock Outlook",
        "My portfolio Risks",
        "Recommended Stocks",
        "Top Dividend Stocks"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.DarkPurpleAppBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !isChatting {
                        Spacer(minLength: 0)

                        headerText(isChatting: false)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)

                        suggestionPills
                            .padding(.bottom, 24)
                    } else {
                        HStack(spacing: 0) {
                            headerText(isChatting: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        messageList
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                                        .combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    inputBar
                }
                .animation(.spring(response: 0.85, dampingFraction: 0.88), value: viewModel.messages.isEmpty)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isChatting {
                        Button {
                            withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                                viewModel.resetSession()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var isChatting: Bool {
        !viewModel.messages.isEmpty
    }

    // MARK: - Header Text
    private func headerText(isChatting: Bool) -> some View {
        Text("What financial insights\ncan i give you today?")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .multilineTextAlignment(isChatting ? .leading : .center)
            .foregroundStyle(Color.white.opacity(isChatting ? 0.7 : 0.95))
            .lineSpacing(isChatting ? 1 : 4)
            .scaleEffect(isChatting ? 0.8 : 1.0, anchor: isChatting ? .leading : .center)
    }

    // MARK: - Suggestion Pills
    private var suggestionPills: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(sampleSuggestions, id: \.self) { suggestion in
                Button {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                        viewModel.send(suggestion, holdings: holdingSummaries)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.PrimaryYellow)
                        Text(suggestion)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.AICardBg)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
    }

    // MARK: - Message List
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("Ask anything...").foregroundColor(Color.white.opacity(0.4))
            )
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.AICardBg)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .focused($isInputFocused)
            .onSubmit {
                guard !isSendDisabled else { return }
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.send(viewModel.inputText, holdings: holdingSummaries)
                }
            }

            Button {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.send(viewModel.inputText, holdings: holdingSummaries)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isSendDisabled ? Color.white.opacity(0.2) : Color.PrimaryYellow)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }
}

#Preview {
    ChatbotView()
}
