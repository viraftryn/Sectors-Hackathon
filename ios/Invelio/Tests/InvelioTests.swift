import XCTest
@testable import Invelio

final class InvelioTests: XCTestCase {
    func testStockDecoding() throws {
        let json = """
        {"ticker": "BBCA", "name": "Bank Central Asia", "price": 9875.0, "change": 1.25}
        """.data(using: .utf8)!

        let stock = try JSONDecoder().decode(Stock.self, from: json)
        XCTAssertEqual(stock.ticker, "BBCA")
        XCTAssertEqual(stock.price, 9875.0)
    }

    func testHoldingLotCalculations() throws {
        let lot = HoldingLot(
            ticker: "BBCA.JK",
            stockName: "Bank Central Asia",
            market: "IDX",
            currency: "IDR",
            pricePerShare: 10000,
            totalInvested: 5000000
        )

        XCTAssertEqual(lot.ticker, "BBCA.JK")
        XCTAssertEqual(lot.shares, 500.0)
        XCTAssertEqual(lot.symbol, "BBCA")
    }
}
