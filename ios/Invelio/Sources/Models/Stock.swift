import Foundation

struct Stock: Codable, Identifiable {
    let ticker: String
    let name: String
    let price: Double
    let change: Double

    var id: String { ticker }
}
