//
//  PortfolioView.swift
//  Invelio
//
//  Displays user portfolio holdings persisted with SwiftData.
//

import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HoldingLot.buyDate, order: .reverse) private var holdingLots: [HoldingLot]

    @State private var liveStocks: [StockItem] = []
    @State private var isRefreshing: Bool = false

    // Stock items loaded from Backend API or fallback to bundled JSON
    private var allStockItems: [StockItem] {
        if !liveStocks.isEmpty {
            return liveStocks
        }
        return SectorsStocksLoader.loadStockItems()
    }

    private struct StockPosition: Identifiable {
        var id: String { ticker }
        let ticker: String
        let name: String
        let market: String
        let currency: String
        let lots: [HoldingLot]
        let currentPrice: Double
        let totalShares: Double
        let totalInvested: Double

        var marketValue: Double {
            totalShares * currentPrice
        }

        var averageCost: Double {
            totalShares > 0 ? totalInvested / totalShares : 0
        }

        var profitLoss: Double {
            marketValue - totalInvested
        }

        var profitLossPct: Double {
            totalInvested > 0 ? (profitLoss / totalInvested) * 100 : 0
        }
    }

    private var positions: [StockPosition] {
        let dict = Dictionary(grouping: holdingLots, by: { $0.ticker })
        return dict.compactMap { (ticker, lots) in
            guard let first = lots.first else { return nil }
            let totalShares = lots.reduce(0) { $0 + $1.shares }
            let totalInvested = lots.reduce(0) { $0 + $1.totalInvested }

            // Find current price from catalog
            let matched = allStockItems.first {
                $0.symbol.uppercased() == first.symbol.uppercased() ||
                ticker.uppercased().hasPrefix($0.symbol.uppercased())
            }
            let currentPrice = matched?.price ?? first.pricePerShare

            return StockPosition(
                ticker: ticker,
                name: first.stockName.isEmpty ? (matched?.name ?? ticker) : first.stockName,
                market: first.market,
                currency: first.currency,
                lots: lots,
                currentPrice: currentPrice,
                totalShares: totalShares,
                totalInvested: totalInvested
            )
        }.sorted { $0.marketValue > $1.marketValue }
    }

    private var totalPortfolioValue: Double {
        positions.reduce(0) { $0 + $1.marketValue }
    }

    private var totalPortfolioCost: Double {
        positions.reduce(0) { $0 + $1.totalInvested }
    }

    private var totalProfitLoss: Double {
        totalPortfolioValue - totalPortfolioCost
    }

    private var totalGrowthPct: Double {
        totalPortfolioCost > 0 ? (totalProfitLoss / totalPortfolioCost) * 100 : 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.DarkPurpleAppBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard

                        if positions.isEmpty {
                            emptyHoldingsView
                        } else {
                            positionsList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await loadPortfolioData()
                }
            }
            .task {
                await loadPortfolioData()
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var dynamicSummary: PortfolioSummaryData {
        let totalVal = totalPortfolioValue
        let totalCost = totalPortfolioCost

        var dailyProfit: Double = 0
        for lot in holdingLots {
            let matched = allStockItems.first {
                $0.symbol.uppercased() == lot.symbol.uppercased() ||
                lot.ticker.uppercased().hasPrefix($0.symbol.uppercased())
            }
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

    // MARK: - Summary Card
    private var summaryCard: some View {
        PortfolioSummaryCardView(
            summary: dynamicSummary,
            holdingLots: holdingLots,
            stockItems: allStockItems,
            title: "Total Portfolio",
            horizontalPadding: 0,
            showChart: true
        )
    }

    // MARK: - Positions List
    private var positionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stock Holdings")
                .font(.headline.bold())
                .foregroundStyle(Color.white)
                .padding(.top, 8)

            ForEach(positions) { pos in
                let matchedStock = allStockItems.first { $0.symbol.uppercased() == pos.ticker.components(separatedBy: ".").first?.uppercased() }
                let destinationView: StockDetailView = {
                    if let stock = matchedStock {
                        return StockDetailView(stock: stock)
                    } else {
                        let quote = StockQuote(
                            ticker: pos.ticker,
                            name: pos.name,
                            price: pos.currentPrice,
                            change: 0,
                            changePercent: 0,
                            previousClose: pos.currentPrice,
                            currency: pos.currency
                        )
                        return StockDetailView(quote: quote)
                    }
                }()

                NavigationLink(destination: destinationView) {
                    positionRow(pos: pos)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func positionRow(pos: StockPosition) -> some View {
        let isProfit = pos.profitLoss >= 0
        let sign = isProfit ? "+" : "-"
        let pColor = isProfit ? Color.ProfitGreen : Color.PortfolioLossRed
        let prefix = StockFormatters.currencyPrefix(for: pos.currency)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pos.ticker)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text(pos.market)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.PrimaryYellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.PrimaryYellow.opacity(0.15), in: Capsule())
                }

                Text(pos.name)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)

                Text(String(format: "%@ Shares • Avg %@%@", formatShares(pos.totalShares), prefix, StockFormatters.stockPrice(pos.averageCost, currency: pos.currency)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(prefix)\(StockFormatters.stockPrice(pos.marketValue, currency: pos.currency))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(String(format: "%@%@%@ (%@%.2f%%)", sign, prefix, StockFormatters.stockPrice(abs(pos.profitLoss), currency: pos.currency), sign, abs(pos.profitLossPct)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(pColor)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty State
    private var emptyHoldingsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 38))
                .foregroundStyle(Color.PrimaryYellow.opacity(0.85))
                .padding(.top, 8)

            Text("No Stock Holdings Yet")
                .font(.headline.bold())
                .foregroundStyle(Color.white)

            Text("Select any stock from the Home tab and add your purchase lots to start tracking your portfolio.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 4)
    }

    private func loadPortfolioData() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. Fetch live stock prices from FastAPI Backend
        do {
            let backendSummaries = try await APIClient.shared.fetchStocks()
            let mapped = backendSummaries.map { $0.toStockItem() }
            if !mapped.isEmpty {
                self.liveStocks = mapped
            }
        } catch {
            // Fallback to bundled data if needed
        }

        // 2. If local holding lots are empty, restore from backend portfolio lots for this device
        if holdingLots.isEmpty {
            do {
                let remoteLots = try await APIClient.shared.fetchHoldingLots()
                if !remoteLots.isEmpty {
                    let isoFormatter = ISO8601DateFormatter()
                    for r in remoteLots {
                        let uuid = UUID(uuidString: r.id) ?? UUID()
                        let buyDate = isoFormatter.date(from: r.buyDate) ?? Date()
                        let restored = HoldingLot(
                            id: uuid,
                            ticker: r.ticker,
                            symbol: r.ticker.components(separatedBy: ".").first ?? r.ticker,
                            stockName: r.stockName ?? r.ticker,
                            market: "IDX",
                            currency: "IDR",
                            buyDate: buyDate,
                            pricePerShare: r.pricePerShare,
                            totalInvested: r.totalInvested,
                            shares: r.shares
                        )
                        modelContext.insert(restored)
                    }
                    try? modelContext.save()
                }
            } catch {
                // Ignore network error on lot sync
            }
        }
    }

    private func formatShares(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.2f", val)
    }
}

#Preview {
    PortfolioView()
}
