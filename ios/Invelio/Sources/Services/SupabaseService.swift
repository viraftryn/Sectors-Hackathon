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
    public static let anonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.placeholder"
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
        let url = restBaseURL.appendingPathComponent(endpoint)
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
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                // Success
            }
        } catch {
            // Silently ignore network failures on offline
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
            let (_, _) = try await session.data(for: request)
        } catch {
            // Offline fallback
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
}
