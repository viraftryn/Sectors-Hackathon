import SwiftUI

struct NotificationView: View {
    @StateObject private var viewModel = AlertViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.DarkPurpleAppBackground.ignoresSafeArea()

                if viewModel.isLoading && viewModel.alerts.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else if let error = viewModel.errorMessage, viewModel.alerts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.5))
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Button("Try again") {
                            Task { await viewModel.loadAlerts() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.PrimaryPurple)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                } else if viewModel.alerts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.5))
                        Text("There's no notification yet")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.alerts) { alert in
                                AlertRow(alert: alert)
                                    .onTapGesture {
                                        Task { await viewModel.markAsRead(alert) }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.DarkPurpleAppBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                    }
                }
            }
            .refreshable {
                await viewModel.triggerScanAndReload()
            }
            .task {
                await viewModel.loadAlerts()
            }
        }
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    let alert: BackendAlert

    private var severityColor: Color {
        switch alert.severity {
        case "high": return Color.LossRed
        case "medium": return Color.PrimaryYellow
        default: return Color.PrimaryPurple
        }
    }

    private var alertIcon: String {
        switch alert.alertType {
        case "price_spike": return "chart.line.uptrend.xyaxis"
        case "volume_surge": return "chart.bar.fill"
        case "sentiment_shift": return "newspaper.fill"
        default: return "bell.fill"
        }
    }

    private var formattedTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        guard let date = formatter.date(from: alert.createdAt)
                ?? fallback.date(from: alert.createdAt) else {
            return alert.createdAt
        }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: alertIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(severityColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let ticker = alert.ticker {
                        Text(ticker)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(severityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer()
                    Text(formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text(alert.message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(alert.isRead ? 0.5 : 0.85))
                    .lineLimit(3)
            }

            if !alert.isRead {
                Circle()
                    .fill(Color.PrimaryPurple)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(alert.isRead ? Color.white.opacity(0.03) : Color.white.opacity(0.07))
        )
    }
}

#Preview {
    NotificationView()
}
