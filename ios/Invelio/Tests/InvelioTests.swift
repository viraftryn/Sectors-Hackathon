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
}
