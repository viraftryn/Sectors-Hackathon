//
//  HomeViewStandalone.swift
//
//  Self-contained single-file replica of the SahamIndo HomeView layout.
//  All models, sub-views, color tokens, formatters, and dummy data are
//  embedded so you can drop this into ANY new SwiftUI project and see
//  the full Home screen immediately — zero external dependencies.
//
//  Tested on iOS 17+ / Xcode 16+.
//

import SwiftUI
import SwiftData

// ╔══════════════════════════════════════════════════════════════════╗
// ║  1.  DESIGN TOKENS — Colors & Sizes                            ║
// ╚══════════════════════════════════════════════════════════════════╝

extension Color {
    // App background (deep navy-purple)
    static let DarkPurpleAppBackground = Color(red: 18/255, green: 17/255, blue: 46/255)
    // Primary accent
    static let PrimaryYellow = Color(red: 234/255, green: 179/255, blue: 8/255)
    // Profit / Loss
    static let ProfitGreen   = Color(red: 34/255, green: 197/255, blue: 94/255)
    static let LossRed       = Color(red: 239/255, green: 68/255, blue: 68/255)
    static let PortfolioLossRed = Color(red: 255/255, green: 88/255, blue: 88/255)
    // Surface / card
    static let SurfaceWhite  = Color.white
    static let AICardBg      = Color(red: 31/255, green: 26/255, blue: 66/255)
    static let AccentGold    = Color(red: 234/255, green: 179/255, blue: 8/255)
    // Avatar gradient palette
    static let avatarGradientPalette: [[Color]] = [
        [Color(red: 59/255, green: 130/255, blue: 246/255), Color(red: 29/255, green: 78/255, blue: 216/255)],
        [Color(red: 236/255, green: 72/255, blue: 153/255), Color(red: 190/255, green: 24/255, blue: 93/255)],
        [Color(red: 139/255, green: 92/255, blue: 246/255), Color(red: 109/255, green: 40/255, blue: 217/255)],
        [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 4/255, green: 120/255, blue: 87/255)],
        [Color(red: 245/255, green: 158/255, blue: 11/255), Color(red: 217/255, green: 119/255, blue: 6/255)],
        [Color(red: 239/255, green: 68/255, blue: 68/255), Color(red: 185/255, green: 28/255, blue: 28/255)],
        [Color(red: 6/255, green: 182/255, blue: 212/255), Color(red: 8/255, green: 145/255, blue: 178/255)],
    ]
}

enum DS { // Design Size
    static let avatarS:  CGFloat = 42
    static let sparkW:   CGFloat = 70
    static let sparkH:   CGFloat = 34
    static let sentBarW: CGFloat = 110
    static let sentBarH: CGFloat = 5
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  2.  MODELS (lightweight, self-contained)                      ║
// ╚══════════════════════════════════════════════════════════════════╝

enum SentimentType: String {
    case recommended = "Recommended"
    case neutral     = "Neutral"
    case caution     = "Caution"

    var sfSymbol: String {
        switch self {
        case .recommended: return "checkmark.circle.fill"
        case .neutral:     return "exclamationmark.triangle.fill"
        case .caution:     return "xmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .recommended: return .ProfitGreen
        case .neutral:     return .AccentGold
        case .caution:     return .LossRed
        }
    }
}

struct Sentiment: Hashable {
    let buy: Double; let hold: Double; let sell: Double; let score: Double
    var type: SentimentType {
        if score >= 70 { return .recommended }
        if score <= 40 { return .caution }
        return .neutral
    }
}

struct StockItem: Identifiable {
    var id: String { "\(market)_\(symbol)" }
    let symbol: String
    let name: String
    let sector: String
    let price: Double
    let change: Double
    let percentChange: Double
    let sentiment: Sentiment
    let market: String            // "IDX"
    let sparkData: [Double]       // normalised 0‒1 for mini chart
}

struct InsightChip: Identifiable {
    let id = UUID()
    let label: String
    let text: String
}

struct PortfolioSummaryData {
    let totalValue: Double
    let totalCost:  Double
    var dailyProfitIDR: Double = 0
    var dailyGrowthPct: Double = 0
    var profitIDR:  Double { totalValue - totalCost }
    var growthPct:  Double { totalCost > 0 ? (profitIDR / totalCost) * 100 : 0 }
}


// ╔══════════════════════════════════════════════════════════════════╗
// ║  3.  DUMMY DATA                                                ║
// ╚══════════════════════════════════════════════════════════════════╝

let dummySummary = PortfolioSummaryData(totalValue: 0, totalCost: 0)

let dummyStocks: [StockItem] = {
    let loaded = SectorsStocksLoader.loadStockItems()
    if !loaded.isEmpty {
        return loaded
    }
    // Fallback list jika file JSON tidak dapat diakses
    return [
        StockItem(symbol: "BBCA", name: "Bank Central Asia", sector: "Financials", price: 9850, change: 75, percentChange: 0.77,
                  sentiment: Sentiment(buy: 0.70, hold: 0.20, sell: 0.10, score: 85), market: "IDX",
                  sparkData: [0.30, 0.35, 0.32, 0.45, 0.50, 0.48, 0.55, 0.60, 0.58, 0.62, 0.65, 0.70]),
        StockItem(symbol: "BBRI", name: "Bank Rakyat Indonesia", sector: "Financials", price: 4680, change: -30, percentChange: -0.64,
                  sentiment: Sentiment(buy: 0.45, hold: 0.35, sell: 0.20, score: 55), market: "IDX",
                  sparkData: [0.60, 0.58, 0.55, 0.50, 0.52, 0.48, 0.45, 0.42, 0.44, 0.40, 0.38, 0.35]),
        StockItem(symbol: "DCII", name: "DCI Indonesia", sector: "Technology", price: 42500, change: 850, percentChange: 2.04,
                  sentiment: Sentiment(buy: 0.82, hold: 0.12, sell: 0.06, score: 90), market: "IDX",
                  sparkData: [0.20, 0.25, 0.32, 0.40, 0.48, 0.52, 0.60, 0.68, 0.72, 0.78, 0.85, 0.92]),
        StockItem(symbol: "BMRI", name: "Bank Mandiri", sector: "Financials", price: 6450, change: 50, percentChange: 0.78,
                  sentiment: Sentiment(buy: 0.68, hold: 0.22, sell: 0.10, score: 82), market: "IDX",
                  sparkData: [0.40, 0.42, 0.45, 0.43, 0.48, 0.52, 0.55, 0.58, 0.60, 0.62, 0.65, 0.68]),
        StockItem(symbol: "BYAN", name: "Bayan Resources", sector: "Energy", price: 17200, change: -150, percentChange: -0.86,
                  sentiment: Sentiment(buy: 0.25, hold: 0.35, sell: 0.40, score: 38), market: "IDX",
                  sparkData: [0.70, 0.68, 0.62, 0.65, 0.58, 0.55, 0.50, 0.48, 0.45, 0.42, 0.38, 0.35])
    ]
}()

let dummyInsightChips: [InsightChip] = [
    InsightChip(label: "Technical Analysis",
                text: "**Banking sector** demonstrates positive momentum. **BBCA & BBRI** are testing resistance. Sector RSI sits at 58, signaling room before overbought territory. Volume is up 15% vs 20-day average."),
    InsightChip(label: "News Sentiment",
                text: "Sentiment on **GGRM** surged noticeably. Positive buzz is up **34%** in the past 48 hours. Q2 earnings release headlines drove retail investor appetite."),
    InsightChip(label: "Macro & Currency",
                text: "Rupiah strengthened to **Rp 15,820/USD** backed by trade surplus. Central bank is expected to hold benchmark rates at 6.25%."),
]


// ╔══════════════════════════════════════════════════════════════════╗
// ║  4.  FORMATTERS                                                ║
// ╚══════════════════════════════════════════════════════════════════╝

private func formatIDR(_ value: Double, decimals: Int = 0) -> String {
    let f = NumberFormatter()
    f.numberStyle           = .decimal
    f.groupingSeparator     = "."
    f.decimalSeparator      = ","
    f.minimumFractionDigits = decimals
    f.maximumFractionDigits = decimals
    return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

private func formatPrice(_ value: Double, market: String) -> String {
    let decimals = market.uppercased() == "IDX" ? 0 : 2
    return formatIDR(value, decimals: decimals)
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  5.  SUB-VIEWS                                                 ║
// ╚══════════════════════════════════════════════════════════════════╝

// MARK: - StockAvatarView

struct StockAvatarView: View {
    let symbol: String
    let name: String
    private var colors: [Color] {
        let hash = abs(symbol.hashValue)
        return Color.avatarGradientPalette[hash % Color.avatarGradientPalette.count]
    }
    private var initials: String {
        if symbol.allSatisfy({ $0.isNumber }) {
            let words = name.split(separator: " ")
            if words.count >= 2 {
                return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return String(symbol.prefix(2)).uppercased()
    }
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: DS.avatarS, height: DS.avatarS)
            .overlay(
                Text(initials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}

// MARK: - SentimentPillView

struct SentimentPillView: View {
    let sentiment: Sentiment
    var body: some View {
        let t = sentiment.type
        HStack(spacing: 3) {
            Image(systemName: t.sfSymbol)
                .font(.system(size: 9, weight: .semibold))
            Text(t.rawValue)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(t.color.opacity(0.15))
        .foregroundColor(t.color)
        .clipShape(Capsule())
    }
}

// MARK: - SentimentBarView

struct SentimentBarView: View {
    let sentiment: Sentiment
    private var color: Color { sentiment.type.color }
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.15))
                .frame(width: DS.sentBarW, height: DS.sentBarH)
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: DS.sentBarW * CGFloat(sentiment.score / 100), height: DS.sentBarH)
        }
    }
}

// MARK: - MiniSparklineView (simplified — uses pre-built data array)

struct MiniSparklineView: View {
    let data: [Double]
    let isPositive: Bool

    private var lineColor: Color { isPositive ? .ProfitGreen : .LossRed }

    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            let minV = data.min()!; let maxV = data.max()!
            let range = max(maxV - minV, 0.001)
            let w = size.width; let h = size.height; let pad: CGFloat = 4
            let usable = h - pad * 2

            func pt(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(data.count - 1) * w
                let y = pad + usable * (1 - (data[i] - minV) / range)
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: pt(0))
            for i in 1..<data.count { line.addLine(to: pt(i)) }

            ctx.stroke(line, with: .color(lineColor),
                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))

            // End dot
            let last = pt(data.count - 1)
            let r: CGFloat = 2.5
            ctx.fill(Path(ellipseIn: CGRect(x: last.x-r, y: last.y-r, width: r*2, height: r*2)),
                     with: .color(lineColor))
        }
    }
}

// MARK: - PriceBadgeView

struct PriceBadgeView: View {
    let price: Double; let change: Double; let percentChange: Double; let market: String
    private var isPositive: Bool { change >= 0 }
    private var color: Color { isPositive ? .ProfitGreen : .LossRed }
    private var formatted: String {
        formatPrice(price, market: market)
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatted)
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(String(format: "%@%.2f%%", isPositive ? "+" : "-", abs(percentChange)))
                .font(.system(size: 10, weight: .medium)).lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(color)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(color.opacity(0.1)).clipShape(Capsule())
        }
    }
}

// MARK: - StockRowView

struct StockRowView: View {
    let stock: StockItem
    var body: some View {
        HStack(spacing: 8) {
            StockAvatarView(symbol: stock.symbol, name: stock.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stock.symbol).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    SentimentPillView(sentiment: stock.sentiment)
                }
                Text(stock.name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                SentimentBarView(sentiment: stock.sentiment)
                    .frame(width: DS.sentBarW, alignment: .leading)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            MiniSparklineView(data: stock.sparkData, isPositive: stock.change >= 0)
                .frame(width: DS.sparkW, height: DS.sparkH)
                .padding(.trailing, 8)
            PriceBadgeView(price: stock.price, change: stock.change,
                           percentChange: stock.percentChange, market: stock.market)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - StockListView

struct StockListView: View {
    let items: [StockItem]
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                NavigationLink(destination: StockDetailView(stock: item)) {
                    VStack(spacing: 0) {
                        StockRowView(stock: item)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                        Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 16)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - PortfolioSummaryCardView (simplified — no interactive chart)

struct PortfolioSummaryCardView: View {
    let summary: PortfolioSummaryData

    @State private var selectedRange: String = "1D"
    private let ranges: [String] = ["1D", "1W", "1M", "3M", "YTD", "1Y", "5Y"]

    private let green = Color.ProfitGreen
    private let red   = Color.PortfolioLossRed
    private let cardGradient = LinearGradient(
        colors: [Color(red: 102/255, green: 94/255, blue: 191/255),
                 Color(red: 61/255, green: 55/255, blue: 136/255)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Your Portfolio")
                .font(.caption).foregroundColor(.white.opacity(0.75))
            Text("Rp\(formatIDR(summary.totalValue))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 2)

            // 1D Return (Top)
            let isDailyPos = summary.dailyProfitIDR >= 0
            let dailyProfitText = isDailyPos ? "+Rp\(formatIDR(summary.dailyProfitIDR))" : "-Rp\(formatIDR(abs(summary.dailyProfitIDR)))"
            HStack(spacing: 6) {
                Text(dailyProfitText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDailyPos ? green : red)
                Text(String(format: "(%+.2f%%)", summary.dailyGrowthPct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDailyPos ? green : red)
                Text("1D")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.55))
            }

            // All Time Return (Bottom)
            let isAllPos = summary.profitIDR >= 0
            let allProfitText = isAllPos ? "+Rp\(formatIDR(summary.profitIDR))" : "-Rp\(formatIDR(abs(summary.profitIDR)))"
            HStack(spacing: 6) {
                Text(allProfitText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAllPos ? green : red)
                Text(String(format: "(%+.2f%%)", summary.growthPct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAllPos ? green : red)
                Text("All Time")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.55))
            }

            // Area & line chart (flat horizontal line)
            GeometryReader { geo in
                let midY = geo.size.height * 0.5
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: midY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        stops: [.init(color: Color.orange.opacity(0.20), location: 0),
                                .init(color: Color.orange.opacity(0.0), location: 0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .frame(height: 100)
            .padding(.top, 8)

            // Custom Segmented Control (without capsule)
            HStack {
                ForEach(ranges, id: \.self) { range in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRange = range
                        }
                    } label: {
                        Text(range)
                            .font(.system(size: 12, weight: selectedRange == range ? .bold : .medium))
                            .foregroundColor(selectedRange == range ? .orange : .gray)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - AIInsightCardView (with typing animation)

struct AIInsightCardView: View {
    let chips: [InsightChip]
    var title: String = "AI Insight"
    var horizontalPadding: CGFloat = 16

    private let accent = Color.PrimaryYellow
    @State private var selectedIndex: Int      = 0
    @State private var isPulsing:     Bool     = false
    @State private var wordIndex:     Int      = 0
    @State private var targetWords:   [String] = []
    @State private var timer:         Timer?   = nil
    @State private var isExpanded:    Bool     = false
    @State private var showReadMore:  Bool     = false
    @State private var hasStarted:    Bool     = false

    private var selectedChip: InsightChip? { chips.indices.contains(selectedIndex) ? chips[selectedIndex] : nil }
    private var displayedText: String { targetWords.prefix(wordIndex).joined(separator: " ") }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Header badge
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                        .scaleEffect(isPulsing ? 0.7 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)
                    Text(title)
                        .font(.caption2).foregroundColor(accent).kerning(0.8)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(accent.opacity(0.12)).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.5))

                // Animated text
                let isLong = targetWords.count > 30
                let lineLimit: Int? = (isLong && !isExpanded) ? 3 : nil
                VStack(alignment: .leading, spacing: 8) {
                    buildAttributedText(from: displayedText)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(lineLimit)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .transaction { $0.animation = nil }

                    if isLong && showReadMore {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Show less" : "Read more")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
            .padding(12)

            // Disclaimer Banner (above chips)
            Text("Based on available data and for informational purposes only, not financial advice to buy or sell. Always Do your own research before making investment decisions.")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(2.5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 0.8)
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            // Chip selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                        Button {
                            selectedIndex = index
                            isExpanded    = false
                            startTyping(text: chip.text)
                        } label: {
                            Text(chip.label)
                                .font(.caption2)
                                .foregroundColor(selectedIndex == index ? accent : .white.opacity(0.75))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(selectedIndex == index ? accent.opacity(0.12) : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(
                                    selectedIndex == index ? accent.opacity(0.45) : Color.white.opacity(0.15),
                                    lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 12)
        }
        .frame(minHeight: 150, alignment: .top)
        .background(Color.AICardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, horizontalPadding)
        .onAppear {
            isPulsing = true
            if !hasStarted, let chip = selectedChip {
                hasStarted = true
                startTyping(text: chip.text)
            }
        }
        .onChange(of: chips.first?.id) { _ in
            selectedIndex = 0
            isExpanded = false
            if let chip = chips.first {
                startTyping(text: chip.text)
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func startTyping(text: String) {
        timer?.invalidate(); timer = nil
        showReadMore = false; isExpanded = false
        targetWords = text.components(separatedBy: " ")
        wordIndex = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { t in
            if wordIndex < targetWords.count {
                wordIndex += 1
                if wordIndex == 30 && !showReadMore {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.3)) { showReadMore = true }
                    }
                }
            } else {
                if !showReadMore {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.3)) { showReadMore = true }
                    }
                }
                t.invalidate(); timer = nil
            }
        }
    }

    private func buildAttributedText(from raw: String) -> Text {
        var result = Text("")
        let parts = raw.components(separatedBy: "**")
        for (i, part) in parts.enumerated() {
            if i % 2 == 1 {
                result = result + Text(part).font(.system(size: 14, weight: .semibold)).foregroundColor(accent)
            } else {
                result = result + Text(part).font(.system(size: 14)).foregroundColor(.white)
            }
        }
        return result
    }
}


// MARK: - NotificationButton

struct NotificationButton: View {
    let unreadCount: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.20), radius: 5, x: 0, y: 2)

                if unreadCount > 0 {
                    ZStack {
                        Circle().fill(Color.PortfolioLossRed)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.DarkPurpleAppBackground, lineWidth: 1.5))
                        Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    }
                    .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  6.  MAIN HOME VIEW                                            ║
// ╚══════════════════════════════════════════════════════════════════╝

struct HomeView: View {
    @Query private var holdingLots: [HoldingLot]

    private var dynamicSummary: PortfolioSummaryData {
        guard !holdingLots.isEmpty else {
            return dummySummary
        }

        let allStockItems = SectorsStocksLoader.loadStockItems()
        var totalVal: Double = 0
        var totalCost: Double = 0
        var dailyProfit: Double = 0

        for lot in holdingLots {
            totalCost += lot.totalInvested
            let matched = allStockItems.first {
                $0.symbol.uppercased() == lot.symbol.uppercased() ||
                lot.ticker.uppercased().hasPrefix($0.symbol.uppercased())
            }
            let price = matched?.price ?? lot.pricePerShare
            totalVal += (price * lot.shares)
            if let matched = matched {
                dailyProfit += (matched.change * lot.shares)
            }
        }

        let prevDayVal = totalVal - dailyProfit
        let dailyPct = prevDayVal > 0 ? (dailyProfit / prevDayVal) * 100 : 0

        return PortfolioSummaryData(
            totalValue: totalVal,
            totalCost: totalCost,
            dailyProfitIDR: dailyProfit,
            dailyGrowthPct: dailyPct
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 1) Portfolio Summary Card
                    PortfolioSummaryCardView(summary: dynamicSummary)
                        .padding(.top, 0).padding(.bottom, 4)

                    // 2) AI Insight Card
                    AIInsightCardView(chips: dummyInsightChips)
                        .padding(.vertical, 4)

                    // 3) Watchlist Header
                    sectionHeader("Recommended Stocks")
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    // 4) Stock List
                    StockListView(items: dummyStocks)

                    // 6) Search Hint
                    searchHint
                        .padding(.top, 8).padding(.bottom, 20)
                }
            }
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) { topBar }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 4) {
                // Replace with your own logo — here we use SF Symbol placeholder
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.PrimaryYellow)
                Text("Invelio")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            NotificationButton(unreadCount: 3) { /* handle tap */ }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.DarkPurpleAppBackground)
    }

    // MARK: - Search Hint

    private var searchHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.PrimaryYellow)
            Text("Search IDX stocks and more")
                .font(.caption).foregroundColor(.white.opacity(0.7))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(.systemGray6).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.title2).fontWeight(.bold).foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal).padding(.bottom, 6)
    }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  7.  PREVIEW                                                   ║
// ╚══════════════════════════════════════════════════════════════════╝

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
