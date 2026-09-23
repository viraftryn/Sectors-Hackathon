//
//  SupabaseService.swift
//  Invelio
//
//  Multi-Device Portfolio Synchronization via Supabase REST API
//

import Foundation
import UIKit

// MARK: - 1. Device Manager (Unique ID per app installation)

public final class DeviceManager: Sendable {
    public static let shared = DeviceManager()

    private let userDefaultsKey = "invelio_unique_device_id"

    private init() {}

    public var deviceId: String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey), !saved.isEmpty {
            return saved
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: userDefaultsKey)
        return newId
    }

    public var deviceName: String {
        UIDevice.current.name
    }

    public var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    public var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

// MARK: - 2. Supabase Configuration

public enum SupabaseConfig: Sendable {
    public static let projectURL = URL(string: "https://zvtuvfamsbwgeawnkwpp.supabase.co")!
    // Set public anon key from Supabase Dashboard > Project Settings > API
    public static let anonKey: String = "sb_publishable_jyOUKXnYdcLVHgGRpp7zCg_wMFxl9vW"
}

// MARK: - 3. Supabase Transfer DTOs

struct SupabaseInstallationPayload: Codable, Sendable {
    let device_id: String
    let device_name: String
    let os_version: String
    let app_version: String
}

struct SupabaseHoldingPayload: Codable, Sendable {
    let id: String
    let device_id: String
    let ticker: String
    let stock_name: String
    let market: String
    let currency: String
    let shares: Double
    let price_per_share: Double
    let total_invested: Double
    let buy_date: String
}

struct SupabaseStockRecord: Codable, Sendable, Identifiable {
    var id: String { ticker }
    let ticker: String
    let symbol: String
    let name: String
    let sector: String?
    let sub_sector: String?
    let price: Double
    let change_pct: Double?
    let market_cap: Double?
    let pe_ttm: Double?
    let pb_mrq: Double?
    let roe_ttm: Double?
    let der_mrq: Double?
    let yield_ttm: Double?
    let week52_high: Double?
    let week52_low: Double?

    func toStockItem() -> StockItem {
        let pct = change_pct ?? 0.0
        let chg = price * (pct / 100.0)
        let cleanName = name
            .replacingOccurrences(of: "PT ", with: "")
            .replacingOccurrences(of: " Tbk.", with: "")
            .replacingOccurrences(of: " Tbk", with: "")
            .replacingOccurrences(of: " (Persero)", with: "")
            .trimmingCharacters(in: .whitespaces)

        return StockItem(
            symbol: ticker,
            name: cleanName,
            sector: sector ?? "IDX",
            price: price,
            change: chg,
            percentChange: pct,
            sentiment: Sentiment(buy: 0.65, hold: 0.25, sell: 0.10, score: 75),
            market: "IDX",
            sparkData: [0.35, 0.40, 0.38, 0.45, 0.50, 0.55, 0.52, 0.58, 0.62, 0.65]
        )
    }

    func toStockFundamentals() -> StockFundamentals {
        StockFundamentals(
            ticker: ticker,
            pe: pe_ttm,
            pb: pb_mrq,
            roe: roe_ttm,
            der: der_mrq,
            dividendYield: yield_ttm,
            week52High: week52_high,
            week52Low: week52_low,
            sector: sector ?? "IDX"
        )
    }

    func toStockQuote() -> StockQuote {
        let pct = change_pct ?? 0.0
        let chg = price * (pct / 100.0)
        return StockQuote(
            ticker: ticker,
            name: name,
            price: price,
            change: chg,
            changePercent: pct,
            previousClose: price - chg,
            currency: "IDR"
        )
    }
}

struct SupabaseDailyPriceRecord: Codable, Sendable {
    let ticker: String
    let date: String
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double
    let volume: Int?

    func toHistoryPoint() -> StockHistoryPoint {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let d = formatter.date(from: date) ?? Date()
        return StockHistoryPoint(date: d, price: close, volume: volume ?? 0)
    }
}

// MARK: - 4. Supabase Service

public actor SupabaseService {
    public static let shared = SupabaseService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    private var restBaseURL: URL {
        SupabaseConfig.projectURL.appendingPathComponent("rest/v1")
    }

    private func makeRequest(endpoint: String, method: String = "GET") -> URLRequest {
        let cleanEndpoint = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        let fullURLString = "\(restBaseURL.absoluteString)/\(cleanEndpoint)"
        guard let url = URL(string: fullURLString) else {
            fatalError("Invalid URL: \(fullURLString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceManager.shared.deviceId, forHTTPHeaderField: "x-device-id")
        return request
    }

    // MARK: - Device Registration
    public func registerDevice() async {
        let payload = SupabaseInstallationPayload(
            device_id: DeviceManager.shared.deviceId,
            device_name: DeviceManager.shared.deviceName,
            os_version: DeviceManager.shared.osVersion,
            app_version: DeviceManager.shared.appVersion
        )

        var request = makeRequest(endpoint: "user_installations", method: "POST")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[Supabase] registerDevice HTTP \(http.statusCode)")
                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("[Supabase] registerDevice failed: \(body)")
                }
            }
        } catch {
            print("[Supabase] registerDevice error: \(error.localizedDescription)")
        }
    }

    // MARK: - Portfolio Holdings Sync
    public func upsertHolding(
        id: UUID,
        ticker: String,
        stockName: String,
        market: String,
        currency: String,
        shares: Double,
        pricePerShare: Double,
        totalInvested: Double,
        buyDate: Date
    ) async {
        let formatter = ISO8601DateFormatter()
        let payload = SupabaseHoldingPayload(
            id: id.uuidString,
            device_id: DeviceManager.shared.deviceId,
            ticker: ticker,
            stock_name: stockName,
            market: market,
            currency: currency,
            shares: shares,
            price_per_share: pricePerShare,
            total_invested: totalInvested,
            buy_date: formatter.string(from: buyDate)
        )

        var request = makeRequest(endpoint: "user_holdings", method: "POST")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[Supabase] upsertHolding HTTP \(http.statusCode) for \(ticker)")
                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("[Supabase] upsertHolding failed: \(body)")
                }
            }
        } catch {
            print("[Supabase] upsertHolding error: \(error.localizedDescription)")
        }
    }

    public func deleteHolding(id: UUID) async {
        var request = makeRequest(endpoint: "user_holdings?id=eq.\(id.uuidString)", method: "DELETE")
        do {
            let (_, _) = try await session.data(for: request)
        } catch {
            // Offline fallback
        }
    }

    func fetchRemoteHoldings() async -> [SupabaseHoldingPayload] {
        let deviceId = DeviceManager.shared.deviceId
        let request = makeRequest(endpoint: "user_holdings?device_id=eq.\(deviceId)&order=buy_date.desc")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            return (try? JSONDecoder().decode([SupabaseHoldingPayload].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    // MARK: - Direct PostgreSQL Reads (0 Sectors API Credits!)

    func fetchStocks() async -> [SupabaseStockRecord] {
        let request = makeRequest(endpoint: "stocks?order=market_cap.desc.nullslast&limit=20")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[Supabase] fetchStocks: invalid response")
                return []
            }
            if !(200...299).contains(http.statusCode) {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                print("[Supabase] fetchStocks failed HTTP \(http.statusCode): \(errBody)")
                return []
            }
            let list = (try? JSONDecoder().decode([SupabaseStockRecord].self, from: data)) ?? []
            print("[Supabase] fetchStocks success: loaded \(list.count) stocks from PostgreSQL")
            return list
        } catch {
            print("[Supabase] fetchStocks error: \(error.localizedDescription)")
            return []
        }
    }

    func fetchStockDetail(ticker: String) async -> SupabaseStockRecord? {
        let clean = ticker.components(separatedBy: ".").first ?? ticker
        let request = makeRequest(endpoint: "stocks?ticker=eq.\(clean)&limit=1")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let list = (try? JSONDecoder().decode([SupabaseStockRecord].self, from: data)) ?? []
            return list.first
        } catch {
            return nil
        }
    }

    func fetchDailyPrices(ticker: String) async -> [StockHistoryPoint] {
        let clean = ticker.components(separatedBy: ".").first ?? ticker
        let request = makeRequest(endpoint: "stock_daily_prices?ticker=eq.\(clean)&order=date.asc")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let list = (try? JSONDecoder().decode([SupabaseDailyPriceRecord].self, from: data)) ?? []
            return list.map { $0.toHistoryPoint() }
        } catch {
            return []
        }
    }
}
