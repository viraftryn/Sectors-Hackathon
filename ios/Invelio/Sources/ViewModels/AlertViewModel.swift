import Foundation

@MainActor
final class AlertViewModel: ObservableObject {
    @Published var alerts: [BackendAlert] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func loadAlerts() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await APIClient.shared.fetchAlerts()
            alerts = result.alerts
            unreadCount = result.unreadCount
        } catch {
            errorMessage = "Failed to load the notifications."
        }
        isLoading = false
    }

    func markAsRead(_ alert: BackendAlert) async {
        guard !alert.isRead else { return }
        do {
            try await APIClient.shared.markAlertRead(alertId: alert.id)
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                let old = alerts[idx]
                alerts[idx] = BackendAlert(
                    id: old.id,
                    ticker: old.ticker,
                    alertType: old.alertType,
                    severity: old.severity,
                    message: old.message,
                    isRead: true,
                    createdAt: old.createdAt
                )
                unreadCount = max(0, unreadCount - 1)
            }
        } catch {
            // Silently fail — next refresh will sync state
        }
    }

    func triggerScanAndReload() async {
        do {
            try await APIClient.shared.triggerAlertScan()
        } catch {
            // Scan failure is non-critical
        }
        await loadAlerts()
    }
}
