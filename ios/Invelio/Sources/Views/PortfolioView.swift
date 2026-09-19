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

    // Stock items loaded from JSON to get real-time / latest closing prices
    private var allStockItems: [StockItem] {
        SectorsStocksLoader.loadStockItems()
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

                if positions.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard
                            positionsList
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total Portfolio Value")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.65))

            Text("Rp \(StockFormatters.stockPrice(totalPortfolioValue, currency: "IDR"))")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            HStack(spacing: 8) {
                let isProfit = totalProfitLoss >= 0
                let sign = isProfit ? "+" : "-"
                let pColor = isProfit ? Color.ProfitGreen : Color.PortfolioLossRed

                HStack(spacing: 4) {
                    Image(systemName: isProfit ? "arrow.up.right" : "arrow.down.forward")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%@Rp %@ (%@%.2f%%)", sign, StockFormatters.stockPrice(abs(totalProfitLoss), currency: "IDR"), sign, abs(totalGrowthPct)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(pColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pColor.opacity(0.15), in: Capsule())

                Spacer()

                Text(positions.count == 1 ? "1 Stock" : "\(positions.count) Stocks")
                    .font(.caption.bold())
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 45/255, green: 38/255, blue: 95/255), Color(red: 26/255, green: 22/255, blue: 58/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie")
                .font(.system(size: 54))
                .foregroundStyle(Color.PrimaryYellow.opacity(0.8))

            Text("No Stock Holdings Yet")
                .font(.title3.bold())
                .foregroundStyle(Color.white)

            Text("Select any stock from the Home tab and add your purchase lots to start tracking your portfolio.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatShares(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.2f", val)
    }
}

#Preview {
    PortfolioView()
}
