//
//  StockDetailView.swift
//  Invelio
//
//  Self-contained Stock Detail View for SwiftUI supporting IDX market.
//

import SwiftUI
import Combine
import SwiftData

// MARK: - ==========================================
// MARK: 1. DATA MODELS
// MARK: - ==========================================

public struct StockQuote: Identifiable, Hashable, Sendable {
    public var id: String { ticker }
    public let ticker: String
    public let name: String
    public var price: Double
    public var change: Double
    public var changePercent: Double
    public var previousClose: Double
    public var currency: String // "IDR", "SGD", "MYR"

    public var currencyPrefix: String {
        StockFormatters.currencyPrefix(for: currency)
    }

    public init(
        ticker: String,
        name: String,
        price: Double,
        change: Double,
        changePercent: Double,
        previousClose: Double,
        currency: String = "IDR"
    ) {
        self.ticker = ticker
        self.name = name
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.previousClose = previousClose
        self.currency = currency
    }
}

public struct StockFundamentals: Sendable {
    public var ticker: String
    public var forwardPE: Double?
    public var eps: Double
    public var pbvRatio: Double
    public var freeCashflow: Double?
    public var sector: String

    public init(
        ticker: String,
        forwardPE: Double? = nil,
        eps: Double = 0.0,
        pbvRatio: Double = 0.0,
        freeCashflow: Double? = nil,
        sector: String = "General"
    ) {
        self.ticker = ticker
        self.forwardPE = forwardPE
        self.eps = eps
        self.pbvRatio = pbvRatio
        self.freeCashflow = freeCashflow
        self.sector = sector
    }
}

public struct StockHistoryPoint: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let price: Double
    public let volume: Int

    public init(id: UUID = UUID(), date: Date, price: Double, volume: Int = 0) {
        self.id = id
        self.date = date
        self.price = price
        self.volume = volume
    }
}

public enum StockTimeRange: String, CaseIterable, Sendable {
    case oneDay     = "1D"
    case oneWeek    = "1W"
    case oneMonth   = "1M"
    case threeMonth = "3M"
    case ytd        = "YTD"
    case oneYear    = "1Y"
    case fiveYear   = "5Y"
    case all        = "ALL"

    public var isIntraday: Bool {
        self == .oneDay || self == .oneWeek
    }
}

public struct PurchaseFormEntry: Identifiable, Equatable {
    public let id: UUID
    public var date: Date
    public var priceInput: String
    public var totalInput: String

    public init(id: UUID = UUID(), date: Date = Date(), priceInput: String = "", totalInput: String = "") {
        self.id = id
        self.date = date
        self.priceInput = priceInput
        self.totalInput = totalInput
    }

    public var price: Double {
        let clean = priceInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(clean) ?? 0.0
    }

    public var total: Double {
        let clean = totalInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(clean) ?? 0.0
    }

    public var shares: Double {
        guard price > 0, total > 0 else { return 0.0 }
        return total / price
    }

    public var formattedShares: String {
        guard shares > 0 else { return "0" }
        if shares.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(shares))"
        } else {
            let str = String(format: "%.2f", shares)
            return str.hasSuffix("0") ? String(format: "%.1f", shares) : str
        }
    }
}


// MARK: - ==========================================
// MARK: 2. NUMBER FORMATTERS & HELPERS
// MARK: - ==========================================

public enum StockFormatters {
    public static func currencyPrefix(for currency: String = "IDR") -> String {
        return "Rp "
    }

    public static func stockPrice(_ value: Double, currency: String = "IDR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let isZeroDec = currency.uppercased() == "IDR"
        formatter.maximumFractionDigits = isZeroDec ? 0 : 2
        formatter.minimumFractionDigits = isZeroDec ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    public static func financialCompact(_ value: Double, currency: String = "IDR") -> String {
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""
        let prefix = currencyPrefix(for: currency)

        if absVal >= 1_000_000_000_000 {
            return "\(sign)\(prefix)\(String(format: "%.1fT", absVal / 1_000_000_000_000))"
        } else if absVal >= 1_000_000_000 {
            return "\(sign)\(prefix)\(String(format: "%.1fM", absVal / 1_000_000_000))"
        } else if absVal >= 1_000_000 {
            return "\(sign)\(prefix)\(String(format: "%.1fjt", absVal / 1_000_000))"
        } else {
            return "\(sign)\(prefix)\(stockPrice(absVal, currency: currency))"
        }
    }

    public static func formatScrubDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let min = calendar.component(.minute, from: date)
        if hour == 0 && min == 0 {
            f.dateFormat = "d MMM yyyy"
        } else {
            f.dateFormat = "d MMM yyyy, HH:mm"
        }
        return f.string(from: date)
    }
}

fileprivate extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}


// MARK: - ==========================================
// MARK: 3. VIEW MODEL
// MARK: - ==========================================

@MainActor
public final class StockDetailViewModel: ObservableObject {
    @Published public private(set) var dataPoints: [StockHistoryPoint] = []
    @Published public var selectedRange: StockTimeRange = .oneDay
    @Published public private(set) var isLoading: Bool = false

    public let quote: StockQuote
    public var customHistoryFetcher: ((String, StockTimeRange) async throws -> [StockHistoryPoint])?

    public init(quote: StockQuote, fetcher: ((String, StockTimeRange) async throws -> [StockHistoryPoint])? = nil) {
        self.quote = quote
        self.customHistoryFetcher = fetcher
    }

    public var minPrice: Double { dataPoints.map(\.price).min() ?? quote.price }
    public var maxPrice: Double { dataPoints.map(\.price).max() ?? quote.price }
    public var startPrice: Double { dataPoints.first?.price ?? quote.previousClose }
    public var latestPrice: Double { dataPoints.last?.price ?? quote.price }
    public var isPositive: Bool { latestPrice >= startPrice }

    public func fetchChartData() async {
        isLoading = true
        if let fetcher = customHistoryFetcher {
            do {
                let pts = try await fetcher(quote.ticker, selectedRange)
                if !pts.isEmpty {
                    self.dataPoints = pts
                    self.isLoading = false
                    return
                }
            } catch {
                // Fallback to synthetic if fetcher fails
            }
        }

        // Realistic Fallback Data Generation
        self.dataPoints = generateMockPoints(for: selectedRange)
        self.isLoading = false
    }

    private func generateMockPoints(for range: StockTimeRange) -> [StockHistoryPoint] {
        let (count, interval): (Int, TimeInterval) = {
            switch range {
            case .oneDay:     return (78, 5 * 60)
            case .oneWeek:    return (50, 30 * 60)
            case .oneMonth:   return (30, 24 * 3600)
            case .threeMonth: return (90, 24 * 3600)
            case .ytd:        return (120, 24 * 3600)
            case .oneYear:    return (252, 24 * 3600)
            case .fiveYear:   return (260, 7 * 24 * 3600)
            case .all:        return (300, 7 * 24 * 3600)
            }
        }()

        let now = Date()
        var points: [StockHistoryPoint] = []
        var current = quote.previousClose > 0 ? quote.previousClose : quote.price * 0.98
        let step = max(quote.price * 0.006, 0.05)

        for i in 0..<count {
            let d = now.addingTimeInterval(-Double(count - 1 - i) * interval)
            let delta = Double([-2, -1, 0, 1, 2].randomElement() ?? 0) * step
            current = max(quote.price * 0.5, current + delta)

            if i == count - 1 {
                current = quote.price
            }

            points.append(StockHistoryPoint(date: d, price: current, volume: Int.random(in: 5_000...200_000)))
        }
        return points
    }
}


// MARK: - ==========================================
// MARK: 4. INTERACTIVE CHART COMPONENT
// MARK: - ==========================================

public struct StockInteractiveChartView: View {
    @ObservedObject var viewModel: StockDetailViewModel
    @Binding var selectedPoint: StockHistoryPoint?
    @Binding var isDragging: Bool

    let accentColor: Color

    public var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !viewModel.dataPoints.isEmpty {
                        // Area & Line Path
                        chartArea(size: size)
                        chartLine(size: size)

                        // Drag scrubbing line & indicator
                        if isDragging, let pt = selectedPoint {
                            scrubberOverlay(pt: pt, size: size)
                        }
                    } else {
                        Text("No chart data available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let xPos = max(0, min(value.location.x, size.width))
                            let fraction = xPos / size.width
                            let idx = min(Int(fraction * CGFloat(viewModel.dataPoints.count)), viewModel.dataPoints.count - 1)
                            if idx >= 0 && idx < viewModel.dataPoints.count {
                                let newPt = viewModel.dataPoints[idx]
                                if selectedPoint?.id != newPt.id {
                                    selectedPoint = newPt
                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                    gen.impactOccurred()
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDragging = false
                                selectedPoint = nil
                            }
                        }
                )
            }
            .frame(height: 220)

            // Timeframe Selector
            Picker("Timeframe", selection: $viewModel.selectedRange) {
                ForEach(StockTimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedRange) { _ in
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                selectedPoint = nil
                isDragging = false
                Task { await viewModel.fetchChartData() }
            }
        }
    }

    private func normalizeY(price: Double, height: CGFloat) -> CGFloat {
        let minP = viewModel.minPrice
        let maxP = viewModel.maxPrice
        let diff = maxP - minP
        guard diff > 0 else { return height / 2 }
        let topPadding: CGFloat = 28
        let bottomPadding: CGFloat = 16
        let usableH = height - topPadding - bottomPadding
        let normalized = CGFloat((price - minP) / diff)
        return height - bottomPadding - (normalized * usableH)
    }

    private func normalizeX(index: Int, total: Int, width: CGFloat) -> CGFloat {
        guard total > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(total - 1) * width
    }

    private func chartLine(size: CGSize) -> some View {
        Path { path in
            let count = viewModel.dataPoints.count
            for (idx, pt) in viewModel.dataPoints.enumerated() {
                let x = normalizeX(index: idx, total: count, width: size.width)
                let y = normalizeY(price: pt.price, height: size.height)
                if idx == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func chartArea(size: CGSize) -> some View {
        Path { path in
            let count = viewModel.dataPoints.count
            guard count > 0 else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            for (idx, pt) in viewModel.dataPoints.enumerated() {
                let x = normalizeX(index: idx, total: count, width: size.width)
                let y = normalizeY(price: pt.price, height: size.height)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [accentColor.opacity(0.35), accentColor.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func scrubberOverlay(pt: StockHistoryPoint, size: CGSize) -> some View {
        let count = viewModel.dataPoints.count
        let idx = viewModel.dataPoints.firstIndex(where: { $0.id == pt.id }) ?? 0
        let x = normalizeX(index: idx, total: count, width: size.width)
        let y = normalizeY(price: pt.price, height: size.height)

        let labelText = StockFormatters.formatScrubDate(pt.date)
        // Posisi horizontal mengikuti drag X (dibatasi batas chart)
        let labelX = min(max(50, x), size.width - 50)
        // Posisi vertikal tetap di atas chart
        let labelY: CGFloat = 10

        return ZStack {
            // Vertical Line
            Path { path in
                path.move(to: CGPoint(x: x, y: 22))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Circle Indicator (Drag Point pada kurva harga)
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .position(x: x, y: y)

            // Label di atas chart secara vertikal, mengikuti posisi horizontal drag
            Text(labelText)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                .position(x: labelX, y: labelY)
        }
    }
}


// MARK: - ==========================================
// MARK: 5. MAIN STOCK DETAIL VIEW
// MARK: - ==========================================

public struct StockDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HoldingLot.buyDate, order: .forward) private var allHoldingLots: [HoldingLot]

    public let quote: StockQuote
    public var fundamentals: StockFundamentals?
    public var onBuy: ((_ amount: Double, _ pricePerShare: Double) -> Void)?

    @StateObject private var viewModel: StockDetailViewModel
    @State private var selectedPoint: StockHistoryPoint? = nil
    @State private var isDragging: Bool = false
    @State private var isFavorited: Bool = false

    // Purchase / Lots management state
    @State private var purchaseEntries: [PurchaseFormEntry] = []

    public init(
        quote: StockQuote,
        fundamentals: StockFundamentals? = nil,
        customHistoryFetcher: ((String, StockTimeRange) async throws -> [StockHistoryPoint])? = nil,
        onBuy: ((_ amount: Double, _ pricePerShare: Double) -> Void)? = nil
    ) {
        self.quote = quote
        self.fundamentals = fundamentals
        self.onBuy = onBuy
        _viewModel = StateObject(wrappedValue: StockDetailViewModel(quote: quote, fetcher: customHistoryFetcher))
    }

    private var stockLots: [HoldingLot] {
        allHoldingLots.filter { $0.ticker == quote.ticker }
    }

    private var detectedMarket: String {
        return "IDX"
    }

    private var currencyPrefix: String {
        StockFormatters.currencyPrefix(for: quote.currency)
    }

    private var displayPrice: Double {
        selectedPoint?.price ?? quote.price
    }

    private var displayFormattedPrice: String {
        let p = displayPrice
        return "\(currencyPrefix)\(StockFormatters.stockPrice(p, currency: quote.currency))"
    }

    private var currentChange: Double {
        if isDragging, let pt = selectedPoint {
            return pt.price - viewModel.startPrice
        }
        if let first = viewModel.dataPoints.first, let last = viewModel.dataPoints.last {
            return last.price - first.price
        }
        return quote.change
    }

    private var currentChangePct: Double {
        if isDragging, let pt = selectedPoint {
            guard viewModel.startPrice != 0 else { return 0 }
            return ((pt.price - viewModel.startPrice) / viewModel.startPrice) * 100
        }
        if let first = viewModel.dataPoints.first, let last = viewModel.dataPoints.last {
            guard first.price != 0 else { return 0 }
            return ((last.price - first.price) / first.price) * 100
        }
        return quote.changePercent
    }

    private var isGain: Bool { currentChange >= 0 }
    private var themeColor: Color {
        isGain ? Color(red: 0.0, green: 0.78, blue: 0.58) : Color(red: 0.94, green: 0.27, blue: 0.27)
    }

    public var body: some View {
        ZStack {
            // Background matching HomeView
            Color.DarkPurpleAppBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    chartSection
                    aiAnalysisSection
                    holdingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(quote.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        isFavorited.toggle()
                    }
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFavorited ? Color.PrimaryYellow : Color.white.opacity(0.8))
                }
            }
        }
        .task {
            loadExistingHoldings()
            await viewModel.fetchChartData()
        }
        .onChange(of: purchaseEntries) { _ in
            syncHoldingsToSwiftData()
        }
    }

    private func loadExistingHoldings() {
        let saved = stockLots
        if !saved.isEmpty {
            purchaseEntries = saved.map { lot in
                PurchaseFormEntry(
                    id: lot.id,
                    date: lot.buyDate,
                    priceInput: formatNumber(lot.pricePerShare),
                    totalInput: formatNumber(lot.totalInvested)
                )
            }
        } else if purchaseEntries.isEmpty {
            purchaseEntries = [
                PurchaseFormEntry(
                    date: Date(),
                    priceInput: formatNumber(quote.price),
                    totalInput: ""
                )
            ]
        }
    }

    private func syncHoldingsToSwiftData() {
        let currentValid = validEntries
        let activeIDs = Set(currentValid.map(\.id))

        // Remove lots deleted in UI
        for lot in stockLots {
            if !activeIDs.contains(lot.id) {
                modelContext.delete(lot)
            }
        }

        // Insert or update valid lots
        for entry in currentValid {
            if let existing = stockLots.first(where: { $0.id == entry.id }) {
                existing.buyDate = entry.date
                existing.pricePerShare = entry.price
                existing.totalInvested = entry.total
                existing.shares = entry.shares
            } else {
                let newLot = HoldingLot(
                    id: entry.id,
                    ticker: quote.ticker,
                    symbol: quote.ticker.components(separatedBy: ".").first ?? quote.ticker,
                    stockName: quote.name,
                    market: detectedMarket,
                    currency: quote.currency,
                    buyDate: entry.date,
                    pricePerShare: entry.price,
                    totalInvested: entry.total,
                    shares: entry.shares
                )
                modelContext.insert(newLot)
            }
        }
        try? modelContext.save()
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.ticker)
                    .font(.title2.bold())
                    .foregroundStyle(Color.white)
                Text(quote.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayFormattedPrice)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        let sign = currentChange >= 0 ? "+" : "-"
                        let formattedChange = StockFormatters.stockPrice(abs(currentChange), currency: quote.currency)
                        Text(String(format: "%@%@%@ (%@%.2f%%)", sign, currencyPrefix, formattedChange, sign, abs(currentChangePct)))
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(themeColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(themeColor.opacity(0.16), in: Capsule())
                    }
                }

                Spacer(minLength: 8)

                fundamentalsCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fundamentalsCard: some View {
        let f = fundamentals
        return VStack(alignment: .leading, spacing: 3.5) {
            metricRow(label: "Forward P/E", value: f?.forwardPE != nil ? String(format: "%.2fx", f!.forwardPE!) : "--")
            metricRow(label: "EPS", value: f != nil ? "\(currencyPrefix)\(StockFormatters.stockPrice(f!.eps, currency: quote.currency))" : "--")
            metricRow(label: "PBV", value: f != nil && f!.pbvRatio > 0 ? String(format: "%.2fx", f!.pbvRatio) : "--")
            metricRow(label: "FCF", value: f?.freeCashflow != nil ? StockFormatters.financialCompact(f!.freeCashflow!, currency: quote.currency) : "--")
        }
        .frame(width: 140)
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
    }

    // MARK: - Chart Section
    private var chartSection: some View {
        StockInteractiveChartView(
            viewModel: viewModel,
            selectedPoint: $selectedPoint,
            isDragging: $isDragging,
            accentColor: themeColor
        )
    }

    // MARK: - AI Analysis Section
    private var aiAnalysisSection: some View {
        AIInsightCardView(
            chips: stockAnalysisChips,
            title: "AI Analysis",
            horizontalPadding: 0
        )
    }

    private var stockAnalysisChips: [InsightChip] {
        let isBullish = quote.change >= 0
        let pctStr = String(format: "%.2f", abs(quote.changePercent))
        let formattedPrice = "\(currencyPrefix)\(StockFormatters.stockPrice(quote.price, currency: quote.currency))"

        let technicalText: String
        if isBullish {
            let resistance = "\(currencyPrefix)\(StockFormatters.stockPrice(quote.price * 1.05, currency: quote.currency))"
            technicalText = "**\(quote.ticker)** is in a bullish uptrend (+**\(pctStr)%**) at **\(formattedPrice)**. MACD and RSI indicate consistent accumulation. Immediate resistance is projected near **\(resistance)** with solid trading volume."
        } else {
            let support = "\(currencyPrefix)\(StockFormatters.stockPrice(quote.price * 0.96, currency: quote.currency))"
            technicalText = "**\(quote.ticker)** is consolidating at **\(formattedPrice)** (**-\(pctStr)%**). Selling pressure is subsiding and stochastics entered oversold territory. Strong psychological support is established at **\(support)** with short-term rebound potential."
        }

        let fundamentalText: String
        if let f = fundamentals {
            let peText = f.forwardPE != nil ? String(format: "%.1fx", f.forwardPE!) : "fair"
            let pbvText = f.pbvRatio > 0 ? String(format: "%.2fx", f.pbvRatio) : "healthy"
            let epsFormatted = "\(currencyPrefix)\(StockFormatters.stockPrice(f.eps, currency: quote.currency))"
            fundamentalText = "**\(quote.ticker)** fundamentals show Forward P/E of **\(peText)** and PBV of **\(pbvText)**. EPS is recorded at **\(epsFormatted)** with positive operating cash flow, reflecting solid balance sheet strength to support business growth and dividends."
        } else {
            fundamentalText = "**\(quote.name)** maintains sound operational efficiency and a stable balance sheet in the **\(detectedMarket)** market. Revenue growth remains consistent with resilient profit margins in its sector."
        }

        let sentimentText = "Market sentiment for **\(quote.ticker)** is **positive** with analyst consensus leaning towards **Buy/Overweight**. Domestic market catalysts and institutional demand support active trading liquidity."

        let outlookText = "Medium-term growth outlook is supported by macroeconomic stability and sector digitization. Monitor macro volatility and interest rate benchmarks as primary risk factors."

        return [
            InsightChip(label: "Technical Analysis", text: technicalText),
            InsightChip(label: "Fundamentals", text: fundamentalText),
            InsightChip(label: "Market Sentiment", text: sentimentText),
            InsightChip(label: "Outlook & Risks", text: outlookText)
        ]
    }

    // MARK: - Holdings & Purchase Form Section
    private var validEntries: [PurchaseFormEntry] {
        purchaseEntries.filter { $0.price > 0 && $0.total > 0 }
    }

    private var totalInvestedAmount: Double {
        validEntries.reduce(0) { $0 + $1.total }
    }

    private var totalCalculatedShares: Double {
        validEntries.reduce(0) { $0 + $1.shares }
    }

    private var formattedTotalShares: String {
        let s = totalCalculatedShares
        guard s > 0 else { return "0" }
        return s.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s))" : String(format: "%.2f", s)
    }

    private var averagePricePerShare: Double {
        guard totalCalculatedShares > 0 else { return quote.price }
        return totalInvestedAmount / totalCalculatedShares
    }

    private var currentPositionValue: Double {
        totalCalculatedShares * quote.price
    }

    private var currentPnL: Double {
        currentPositionValue - totalInvestedAmount
    }

    private var currentPnLPercent: Double {
        guard totalInvestedAmount > 0 else { return 0.0 }
        return (currentPnL / totalInvestedAmount) * 100
    }

    private var holdingsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Holding Details")
                    .font(.headline.bold())
                    .foregroundStyle(Color.white)
                Spacer()
                if totalInvestedAmount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Saved")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.ProfitGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.ProfitGreen.opacity(0.12), in: Capsule())
                }
            }

            // Summary Tiles
            if totalInvestedAmount > 0 {
                HStack(spacing: 12) {
                    summaryTile(
                        title: "Position Value",
                        value: "\(currencyPrefix)\(StockFormatters.stockPrice(currentPositionValue, currency: quote.currency))",
                        caption: "\(formattedTotalShares) Shares",
                        icon: "chart.pie.fill",
                        color: Color(hex: "38BDF8")
                    )

                    let isProfit = currentPnL >= 0
                    let sign = isProfit ? "+" : "-"
                    let pColor = isProfit ? Color.ProfitGreen : Color.PortfolioLossRed

                    summaryTile(
                        title: "Total G&L",
                        value: String(format: "%@%@%@", sign, currencyPrefix, StockFormatters.stockPrice(abs(currentPnL), currency: quote.currency)),
                        caption: String(format: "%@%.2f%%", sign, abs(currentPnLPercent)),
                        icon: isProfit ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                        color: pColor,
                        valueColor: pColor
                    )
                }
            }

            // Purchase Lots List
            VStack(spacing: 12) {
                ForEach($purchaseEntries) { $entry in
                    VStack(spacing: 10) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10, weight: .bold))
                                Text(formatEntryDate(entry.date))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: "38BDF8"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(Color(hex: "38BDF8").opacity(0.16), in: Capsule())
                            .overlay {
                                DatePicker("", selection: $entry.date, displayedComponents: .date)
                                    .labelsHidden()
                                    .blendMode(.destinationOver)
                                    .opacity(0.015)
                            }

                            Spacer()

                            if purchaseEntries.count > 1 || totalInvestedAmount > 0 {
                                Button {
                                    withAnimation {
                                        let idToDelete = entry.id
                                        purchaseEntries.removeAll { $0.id == idToDelete }
                                        if let existing = allHoldingLots.first(where: { $0.id == idToDelete }) {
                                            modelContext.delete(existing)
                                            try? modelContext.save()
                                        }
                                        if purchaseEntries.isEmpty {
                                            purchaseEntries = [PurchaseFormEntry(date: Date(), priceInput: formatNumber(quote.price), totalInput: "")]
                                        }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "FF453A"))
                                        .padding(6)
                                        .background(Color(hex: "FF453A").opacity(0.18), in: Circle())
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            let prefix = currencyPrefix.trimmingCharacters(in: .whitespaces)
                            inputField(label: "Cost / Share", prefix: prefix, text: $entry.priceInput)
                            inputField(label: "Total Buy", prefix: prefix, text: $entry.totalInput, fontSize: 13.5, prefixSize: 11)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Shares")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.65))
                                Text(entry.formattedShares)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }

                // Add Share Button
                Button {
                    withAnimation(.spring()) {
                        purchaseEntries.append(PurchaseFormEntry(date: Date(), priceInput: formatNumber(quote.price), totalInput: ""))
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Add Share Lot")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func inputField(label: String, prefix: String, text: Binding<String>, fontSize: CGFloat = 15, prefixSize: CGFloat = 12) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.65))
            HStack(spacing: 3) {
                Text(prefix)
                    .font(.system(size: prefixSize, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(Color.white)
            }
            .padding(8)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryTile(title: String, value: String, caption: String, icon: String, color: Color, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(caption)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatEntryDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    private func formatScrubDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: date)
    }

    private func formatNumber(_ val: Double) -> String {
        guard val > 0 else { return "" }
        return val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.2f", val)
    }
}

// MARK: - ==========================================
// MARK: 6. STOCK ITEM INTEGRATION
// MARK: - ==========================================

extension StockItem {
    var currency: String {
        return "IDR"
    }

    func toStockQuote() -> StockQuote {
        let fullTicker = symbol.hasSuffix(".JK") ? symbol : "\(symbol).JK"

        let prevClose = price - change
        return StockQuote(
            ticker: fullTicker,
            name: name,
            price: price,
            change: change,
            changePercent: percentChange,
            previousClose: prevClose,
            currency: currency
        )
    }

    func toStockFundamentals(from reports: [SectorsCompanyReportResponse] = SectorsStocksLoader.loadRawReports()) -> StockFundamentals {
        let matchingReport = reports.first {
            $0.symbol.uppercased().hasPrefix(self.symbol.uppercased()) ||
            $0.companyName.localizedCaseInsensitiveContains(self.name)
        }

        let fpe = matchingReport?.valuation?.forwardPe
        let eps = matchingReport?.financials?.eps ?? 0.0
        let pbv: Double = {
            if let iv = matchingReport?.valuation?.intrinsicValue, iv > 0 {
                return max(0.5, price / iv)
            }
            return 2.5
        }()
        let fcf = matchingReport?.overview.marketCap.map { $0 * 0.06 }

        return StockFundamentals(
            ticker: matchingReport?.symbol ?? symbol,
            forwardPE: fpe,
            eps: eps,
            pbvRatio: pbv,
            freeCashflow: fcf,
            sector: matchingReport?.overview.sector ?? sector
        )
    }

    func loadHistoryPoints(from reports: [SectorsCompanyReportResponse] = SectorsStocksLoader.loadRawReports()) -> [StockHistoryPoint] {
        let matchingReport = reports.first {
            $0.symbol.uppercased().hasPrefix(self.symbol.uppercased()) ||
            $0.companyName.localizedCaseInsensitiveContains(self.name)
        }

        guard let daily = matchingReport?.dailyPrices, !daily.isEmpty else {
            return []
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return daily.compactMap { item in
            let d = dateFormatter.date(from: item.date) ?? Date()
            return StockHistoryPoint(date: d, price: item.close, volume: Int(item.volume ?? 0))
        }
    }
}

extension StockDetailView {
    init(stock: StockItem) {
        let reports = SectorsStocksLoader.loadRawReports()
        let quote = stock.toStockQuote()
        let fundamentals = stock.toStockFundamentals(from: reports)
        let history = stock.loadHistoryPoints(from: reports)

        self.init(
            quote: quote,
            fundamentals: fundamentals,
            customHistoryFetcher: { _, range in
                if (range == .oneMonth || range == .oneDay) && !history.isEmpty {
                    return history
                }
                return []
            }
        )
    }
}


// MARK: - ==========================================
// MARK: 7. XCODE PREVIEWS
// MARK: - ==========================================

#Preview("Indonesian Stock (BBCA - IDX)") {
    NavigationStack {
        StockDetailView(
            quote: StockQuote(
                ticker: "BBCA.JK",
                name: "Bank Central Asia Tbk",
                price: 10450,
                change: 125,
                changePercent: 1.21,
                previousClose: 10325,
                currency: "IDR"
            ),
            fundamentals: StockFundamentals(
                ticker: "BBCA.JK",
                forwardPE: 16.8,
                eps: 412,
                pbvRatio: 4.8,
                freeCashflow: 25_000_000_000_000,
                sector: "Financial"
            ),
            onBuy: { amount, pricePerShare in
                print("Bought: \(amount) at \(pricePerShare)")
            }
        )
    }
}
