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
    static let PrimaryPurple           = Color(red: 102/255, green: 94/255, blue: 191/255)
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

struct InsightChip: Identifiable, Equatable {
    var id: String { label }
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
// ║  3.  DATA & HELPERS                                            ║
// ╚══════════════════════════════════════════════════════════════════╝

let dummySummary = PortfolioSummaryData(totalValue: 0, totalCost: 0)


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

func formatIDR(_ value: Double, decimals: Int = 0) -> String {
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
    var title: String = "Your Portfolio"
    var horizontalPadding: CGFloat = 16
    var showChart: Bool = false

    @State private var selectedRange: String = "1W"
    private let ranges: [String] = ["1W", "1M", "3M"]

    private let green = Color.ProfitGreen
    private let red   = Color.PortfolioLossRed
    private let cardGradient = LinearGradient(
        colors: [Color(red: 102/255, green: 94/255, blue: 191/255),
                 Color(red: 61/255, green: 55/255, blue: 136/255)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
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

            if showChart {
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
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, showChart ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - AIInsightCardView (with typing animation)

struct AIInsightCardView: View {
    let chips: [InsightChip]
    var title: String = "Market Intelligence"
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
        .onChange(of: chips.first?.text) { newText in
            guard let newText = newText, !newText.isEmpty else { return }
            let currentTarget = targetWords.joined(separator: " ")
            guard newText != currentTarget else { return }
            selectedIndex = 0
            isExpanded = false
            startTyping(text: newText)
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

// MARK: - Invelio Logo View

struct InvelioLogoView: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let uiImage = resolvedLogoImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("invelio-icon")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func resolvedLogoImage() -> UIImage? {
        // 1. Asset Catalog by name
        let names = ["invelio-icon", "Invelio-logo", "invelio-logo", "Invelio-icon"]
        for name in names {
            if let img = UIImage(named: name) {
                return img
            }
        }

        // 2. Main bundle resources
        for name in names {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let img = UIImage(contentsOfFile: path) {
                return img
            }
        }

        // 3. Fallback filesystem search for Xcode Canvas preview
        let candidatePaths = [
            "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Resources/Assets.xcassets/invelio-icon.imageset/Invelio-logo.png",
            "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Sources/Assets.xcassets/invelio-icon.imageset/Invelio-logo.png",
            "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Sources/Views/Assets.xcassets/invelio-icon.imageset/Invelio-logo.png",
            "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Resources/invelio-icon.png",
            "/Users/surya/Documents/2026/Hackaton/Sectors/Sectors-Hackathon-main/ios/Invelio/Sources/invelio-icon.png"
        ]
        for p in candidatePaths {
            if let img = UIImage(contentsOfFile: p) {
                return img
            }
        }

        return nil
    }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  6.  MAIN HOME VIEW                                            ║
// ╚══════════════════════════════════════════════════════════════════╝

struct HomeView: View {
    @Query private var holdingLots: [HoldingLot]
    @State private var liveStocks: [StockItem] = []
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String? = nil
    @State private var showNotifications: Bool = false
    @StateObject private var alertViewModel = AlertViewModel()

    private var displayedStocks: [StockItem] {
        liveStocks
    }

    private var dynamicSummary: PortfolioSummaryData {
        guard !holdingLots.isEmpty else {
            return dummySummary
        }

        let allStockItems = displayedStocks
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

                    // 2) Market Intelligence Card
                    AIInsightCardView(chips: dummyInsightChips)
                        .padding(.vertical, 4)

                    // 3) Watchlist Header
                    sectionHeader("Recommended Stocks")
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    // 4) Stock List from PostgreSQL
                    if isLoading && liveStocks.isEmpty {
                        stocksLoadingPlaceholderView
                    } else if liveStocks.isEmpty {
                        emptyOrRetryView
                    } else {
                        StockListView(items: displayedStocks)
                    }

                    // 5) Search Hint
                    searchHint
                        .padding(.top, 8).padding(.bottom, 20)
                }
            }
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) { topBar }
            .task {
                await loadStocksFromPostgres()
                await alertViewModel.loadAlerts()
            }
            .refreshable {
                await loadStocksFromPostgres()
                await alertViewModel.loadAlerts()
            }
            .fullScreenCover(isPresented: $showNotifications) {
                NotificationView()
            }
            .onChange(of: showNotifications) {
                if !showNotifications {
                    Task { await alertViewModel.loadAlerts() }
                }
            }
        }
    }

    private func loadStocksFromPostgres() async {
        if liveStocks.isEmpty {
            await MainActor.run {
                self.isLoading = true
                self.loadErrorMessage = nil
            }
        }

        // 1. Fetch from FastAPI Backend
        do {
            let backendStocks = try await APIClient.shared.fetchStocks()
            if !backendStocks.isEmpty {
                await MainActor.run {
                    self.liveStocks = backendStocks.map { $0.toStockItem() }
                    self.isLoading = false
                }
                return
            }
        } catch {
            // Fallback to local seeds if backend unavailable
        }

        // 2. Offline / local fallback from seeded sectors_stocks.json
        let localSeeds = SectorsStocksLoader.loadStockItems()
        await MainActor.run {
            if !localSeeds.isEmpty {
                self.liveStocks = localSeeds
            } else {
                self.loadErrorMessage = "Belum dapat memuat data saham dari PostgreSQL."
            }
            self.isLoading = false
        }
    }

    // MARK: - Skeleton Shimmer Loading Placeholder

    private var stocksLoadingPlaceholderView: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: DS.avatarS, height: DS.avatarS)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 50, height: 14)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 110, height: 10)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 75, height: 14)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 50, height: 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Empty or Retry View

    private var emptyOrRetryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 32))
                .foregroundColor(.PrimaryYellow)
            Text(loadErrorMessage ?? "Belum ada data saham dari PostgreSQL.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button(action: {
                Task {
                    await loadStocksFromPostgres()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Muat Ulang")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.PrimaryPurple)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }


    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                InvelioLogoView(size: 28)
                Text("Invelio")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            NotificationButton(unreadCount: alertViewModel.unreadCount) {
                showNotifications = true
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
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
        .padding(.horizontal, 16)
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
