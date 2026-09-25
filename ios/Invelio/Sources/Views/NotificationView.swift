import SwiftUI

// MARK: - Notification Filter Enum

enum AlertFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"

    var id: String { rawValue }
}

// MARK: - Notification View

struct NotificationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var alerts: [BackendAlert] = []
    @State private var unreadCount: Int = 0
    @State private var selectedFilter: AlertFilterTab = .all
    @State private var isLoading: Bool = true
    @State private var isScanning: Bool = false
    @State private var errorMessage: String? = nil

    private var filteredAlerts: [BackendAlert] {
        switch selectedFilter {
        case .all:
            return alerts
        case .unread:
            return alerts.filter { !$0.isRead }
        }
    }

    var body: some View {
        ZStack {
            Color.DarkPurpleAppBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if isLoading && alerts.isEmpty {
                    loadingPlaceholderView
                } else if let error = errorMessage, alerts.isEmpty {
                    errorStateView(error: error)
                } else if filteredAlerts.isEmpty {
                    emptyStateView
                } else {
                    alertsList
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle("Market Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.DarkPurpleAppBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await scanForAlerts() }
                } label: {
                    HStack(spacing: 4) {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.PrimaryYellow)
                        } else {
                            Image(systemName: "sparkles")
                                .foregroundColor(.PrimaryYellow)
                        }
                        Text(isScanning ? "Scanning..." : "Scan")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.PrimaryYellow)
                    }
                }
                .disabled(isScanning)

                if unreadCount > 0 {
                    Button {
                        Task { await markAllAsRead() }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .help("Mark all as read")
                }
            }
        }
        .task {
            await loadAlerts()
        }
        .refreshable {
            await loadAlerts()
        }
    }


    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(AlertFilterTab.allCases) { tab in
                let isSelected = selectedFilter == tab
                let count = tab == .unread ? unreadCount : alerts.count

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        isSelected
                                            ? Color.PrimaryYellow.opacity(0.25)
                                            : Color.white.opacity(0.12)
                                    )
                                )
                                .foregroundColor(isSelected ? .PrimaryYellow : .white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.AICardBg : Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.PrimaryPurple.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Alerts List

    private var alertsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredAlerts) { alert in
                    AlertCardView(alert: alert) {
                        Task { await markAsRead(alert: alert) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholderView: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.AICardBg.opacity(0.6))
                    .frame(height: 100)
                    .overlay(
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 70, height: 18)
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 50, height: 14)
                            }
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(maxWidth: .infinity, maxHeight: 14)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 180, height: 12)
                        }
                        .padding(14)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.PrimaryPurple.opacity(0.35), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: selectedFilter == .unread ? "checkmark.seal.fill" : "bell.slash.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.PrimaryYellow)
            }

            Text(selectedFilter == .unread ? "All Caught Up!" : "No Market Alerts Yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text(
                selectedFilter == .unread
                    ? "You don't have any unread market alerts."
                    : "The Alert Agent scans top gainers, losers, most traded, and news sentiment to detect anomalies."
            )
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            Button {
                Task { await scanForAlerts() }
            } label: {
                HStack(spacing: 6) {
                    if isScanning {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isScanning ? "Scanning..." : "Scan Market Now")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.PrimaryYellow)
                )
            }
            .disabled(isScanning)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Error State View

    private func errorStateView(error: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundColor(.LossRed)

            Text("Failed to Load Alerts")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task { await loadAlerts() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.PrimaryYellow)
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Actions & Data Loading

    private func loadAlerts() async {
        do {
            let res = try await APIClient.shared.fetchAlerts(unreadOnly: false)
            await MainActor.run {
                self.alerts = res.alerts
                self.unreadCount = res.unreadCount
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func scanForAlerts() async {
        await MainActor.run {
            self.isScanning = true
        }
        do {
            try await APIClient.shared.triggerAlertScan()
            await loadAlerts()
        } catch {
            // Even if scan errors or backend throws, reload alerts
            await loadAlerts()
        }
        await MainActor.run {
            self.isScanning = false
        }
    }

    private func markAsRead(alert: BackendAlert) async {
        guard !alert.isRead else { return }

        // Optimistically update locally
        if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[idx] = BackendAlert(
                id: alert.id,
                ticker: alert.ticker,
                alertType: alert.alertType,
                severity: alert.severity,
                message: alert.message,
                isRead: true,
                createdAt: alert.createdAt
            )
            unreadCount = max(0, unreadCount - 1)
        }

        do {
            try await APIClient.shared.markAlertRead(alertId: alert.id)
        } catch {
            // revert or reload on failure
            await loadAlerts()
        }
    }

    private func markAllAsRead() async {
        // Optimistically update
        alerts = alerts.map {
            BackendAlert(
                id: $0.id,
                ticker: $0.ticker,
                alertType: $0.alertType,
                severity: $0.severity,
                message: $0.message,
                isRead: true,
                createdAt: $0.createdAt
            )
        }
        unreadCount = 0

        do {
            try await APIClient.shared.markAllAlertsRead()
        } catch {
            await loadAlerts()
        }
    }
}

// MARK: - Alert Card View

struct AlertCardView: View {
    let alert: BackendAlert
    let onMarkRead: () -> Void

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: alert.createdAt)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: alert.createdAt)
        }

        guard let validDate = date else { return alert.createdAt }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: validDate, relativeTo: Date())
    }

    private var typeIcon: String {
        switch alert.alertType {
        case "price_spike":
            return "chart.line.uptrend.xyaxis"
        case "volume_surge":
            return "chart.bar.fill"
        case "sentiment_shift":
            return "newspaper.fill"
        default:
            return "bell.fill"
        }
    }

    private var typeTitle: String {
        switch alert.alertType {
        case "price_spike":
            return "Price Spike"
        case "volume_surge":
            return "Volume Surge"
        case "sentiment_shift":
            return "Sentiment Shift"
        default:
            return alert.alertType.capitalized
        }
    }

    private var severityColor: Color {
        switch alert.severity.lowercased() {
        case "high":
            return Color.LossRed
        case "medium":
            return Color.PrimaryYellow
        default:
            return Color.PrimaryPurple
        }
    }

    var body: some View {
        Button(action: onMarkRead) {
            VStack(alignment: .leading, spacing: 10) {
                // Top header: Ticker + Type + Severity + Time
                HStack(alignment: .center, spacing: 8) {
                    if let ticker = alert.ticker, !ticker.isEmpty {
                        Text(ticker)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.PrimaryPurple.opacity(0.4))
                            )
                    }

                    // Alert Type badge
                    HStack(spacing: 4) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 11))
                        Text(typeTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.85))

                    // Severity badge
                    Text(alert.severity.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(severityColor.opacity(0.2))
                        )
                        .overlay(
                            Capsule().stroke(severityColor.opacity(0.7), lineWidth: 1)
                        )
                        .foregroundColor(severityColor)

                    Spacer()

                    // Time
                    Text(formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))

                    // Unread dot indicator
                    if !alert.isRead {
                        Circle()
                            .fill(Color.PrimaryYellow)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.PrimaryYellow.opacity(0.8), radius: 3)
                    }
                }

                // Message body
                Text(alert.message)
                    .font(.system(size: 13, weight: alert.isRead ? .regular : .medium))
                    .foregroundColor(alert.isRead ? .white.opacity(0.7) : .white)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.AICardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                !alert.isRead
                                    ? Color.PrimaryYellow.opacity(0.35)
                                    : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(!alert.isRead ? 0.25 : 0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NotificationView()
}
