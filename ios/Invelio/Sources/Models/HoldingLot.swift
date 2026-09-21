//
//  HoldingLot.swift
//  Invelio
//
//  SwiftData persistent model for user stock holding lots.
//

import Foundation
import SwiftData

@Model
public final class HoldingLot {
    @Attribute(.unique) public var id: UUID = UUID()
    public var ticker: String = ""
    public var symbol: String = ""
    public var stockName: String = ""
    public var market: String = "IDX"
    public var currency: String = "IDR"
    public var buyDate: Date = Date()
    public var pricePerShare: Double = 0.0
    public var totalInvested: Double = 0.0
    public var shares: Double = 0.0
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        ticker: String,
        symbol: String = "",
        stockName: String = "",
        market: String = "IDX",
        currency: String = "IDR",
        buyDate: Date = Date(),
        pricePerShare: Double = 0.0,
        totalInvested: Double = 0.0,
        shares: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ticker = ticker
        self.symbol = symbol.isEmpty ? (ticker.components(separatedBy: ".").first ?? ticker) : symbol
        self.stockName = stockName
        self.market = market
        self.currency = currency
        self.buyDate = buyDate
        self.pricePerShare = pricePerShare
        self.totalInvested = totalInvested
        self.shares = shares ?? (pricePerShare > 0 ? totalInvested / pricePerShare : 0.0)
        self.createdAt = createdAt
    }
}
