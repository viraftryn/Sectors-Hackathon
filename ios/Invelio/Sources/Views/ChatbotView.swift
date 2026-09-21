import SwiftUI

// MARK: - Message Model
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - View Model
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isProcessing: Bool = false

    func send(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }

        // Tambahkan pesan user
        let userMessage = ChatMessage(text: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        // Placeholder respon bot
        let botMessageId = UUID()
        let placeholderBotMessage = ChatMessage(
            id: botMessageId,
            text: "",
            isUser: false,
            timestamp: Date()
        )
        messages.append(placeholderBotMessage)

        // Simulasikan delay dan respon bot langsung tanpa card analisis
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let answer = generateDummyAnswer(for: trimmed)
            finalizeBotResponse(messageId: botMessageId, text: answer)
            isProcessing = false
        }
    }

    private func finalizeBotResponse(messageId: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index] = ChatMessage(
            id: messageId,
            text: text,
            isUser: false,
            timestamp: Date()
        )
    }

    func resetSession() {
        messages.removeAll()
        inputText = ""
        isProcessing = false
    }

    private func generateDummyAnswer(for query: String) -> String {
        let q = query.uppercased()

        if q.contains("OUTLOOK") || (q.contains("STOCK") && q.contains("MY")) {
            return """
            **My Stock Outlook**

            • **Overall Trend:** Bullish across banking and defensive consumer sectors.
            • **Top Movers:** BBCA (+0.77%), BMRI (+0.78%), DCII (+2.04%).
            • **Key Catalyst:** Quarterly earnings beating consensus and Rupiah exchange rate stability.

            **Strategic Action:**
            Maintain positions in big-cap leaders and accumulate on pullbacks near support.
            """
        } else if q.contains("RISK") || q.contains("PORTFOLIO") {
            return """
            **Portfolio Risk Assessment**

            • **Risk Level:** Moderate
            • **Sector Concentration:** 65% Financials, 20% Technology, 15% Energy
            • **30-Day Volatility (Beta):** 0.92 (below IDX Composite volatility)

            **Potential Risks & Mitigation:**
            1. **Energy Sector (BYAN):** Exposed to global commodity pullbacks. Periodic rebalancing recommended.
            2. **Diversification:** Consider increasing allocation in Consumer Non-Cyclicals or Healthcare to hedge short-term swings.
            """
        } else if q.contains("RECOMMENDED") || q.contains("REKOMENDASI") {
            return """
            **Recommended Stocks (Top Picks)**

            1. **BBCA (Bank Central Asia)**
               • Target Price: Rp 10,500 | Rating: BUY
               • Catalyst: Solid net interest margins & consistent loan growth.

            2. **DCII (DCI Indonesia)**
               • Target Price: Rp 46,000 | Rating: STRONG BUY
               • Catalyst: AI boom demand and hyperscale data center capacity expansion.

            3. **BMRI (Bank Mandiri)**
               • Target Price: Rp 7,100 | Rating: ACCUMULATE
               • Catalyst: Digital banking efficiency and attractive dividend yield (>5%).
            """
        } else if q.contains("MOVE") || q.contains("WHY") {
            return """
            **Why Did Your Stocks Move Today?**

            • **Positive Market Sentiment:** IDX Composite rallied backed by Rp 450B foreign inflow into financials.
            • **BBCA & BMRI:** Advanced on solid banking liquidity and expansive NIM outlook.
            • **DCII (+2.04%):** Driven by cloud computing demand and regional AI investment momentum.
            • **BYAN (-0.86%):** Pressured by profit taking following Newcastle coal price correction.
            """
        } else if q.contains("BBCA") || q.contains("BCA") {
            return """
            **Analysis: PT Bank Central Asia Tbk (BBCA)**

            • **Recommendation:** BUY / ACCUMULATE
            • **Consensus Target Price:** Rp 11,250 (+12.5%)
            • **Current Valuation:** P/E 22.4x | PBV 4.8x | ROE 23.1%
            • **Dividend Yield:** ~3.1% p.a.

            **Key Takeaways:**
            1. Highest asset quality in the banking sector with CASA ratio above 80%.
            2. Consistent 13-14% YoY loan growth driven by commercial and consumer segments.
            3. Stable BI rate expectations provide headroom for net interest margin (NIM) growth.

            *Conclusion: Well-suited for medium to long-term investors with a conservative risk profile.*
            """
        } else if q.contains("ASII") || q.contains("ASTRA") {
            return """
            **Analysis: PT Astra International Tbk (ASII)**

            • **Recommendation:** NEUTRAL / HOLD
            • **Target Price:** Rp 5,600 (+6.2%)
            • **Current Valuation:** P/E 6.8x | PBV 0.9x (Undervalued)
            • **Dividend Yield:** Highly Attractive (~7.8% p.a.)

            **Risks & Opportunities:**
            • Margin pressure from new EV entrants in the Indonesian auto market.
            • Heavy equipment (UNTR) and agribusiness diversification provide resilient cash flows.
            • Dividend payout ratio remains high above 50%.
            """
        } else if q.contains("TLKM") || q.contains("TELKOM") {
            return """
            **Analysis: PT Telkom Indonesia Tbk (TLKM)**

            • **Recommendation:** BUY
            • **Target Price:** Rp 3,450 (+15.0%)
            • **Current Valuation:** P/E 14.2x | PBV 2.3x | Dividend Yield ~4.8%

            **Key Drivers:**
            1. FMC integration (IndiHome to Telkomsel) drives operational efficiency and ARPU.
            2. Data Center monetization via NeutraDC creates significant unlock value into 2026.
            """
        } else if q.contains("DIVIDEN") || q.contains("DIVIDEND") {
            return """
            **Top High Dividend Yield Stocks on IDX**

            1. **ASII** - Est. Yield 7.8% | Payout ~50%
            2. **PTBA** - Est. Yield 11.2% | Payout ~75%
            3. **ITMG** - Est. Yield 12.5% | Payout ~65%
            4. **BMRI** - Est. Yield 5.1% | Payout ~60%
            5. **BBRI** - Est. Yield 5.4% | Payout ~70%

            *Tip: Track the Cum Date schedule and ensure operating cash flow remains strong.*
            """
        } else {
            return """
            **Market Summary & Analysis**

            Regarding your query: *"\(query)"*

            • **Market Sentiment:** Net foreign inflow remains positive across banking and telco sectors.
            • **IDX Valuation:** Average IDX P/E is ~13.8x, below the 5-year historical average (attractive valuation).
            • **Key Catalysts:** Rupiah exchange stability, controlled domestic inflation, and robust quarterly earnings.

            *💡 You can also ask about specific tickers like BBCA, ASII, TLKM, or dividend recommendations.*
            """
        }
    }
}

// MARK: - Chat Bubble Row
struct ChatBubbleRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 44)
                userBubble
            } else {
                botBubble
                Spacer(minLength: 44)
            }
        }
    }

    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 65/255, green: 55/255, blue: 135/255),
                                Color(red: 45/255, green: 38/255, blue: 95/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }

    private var botBubble: some View {
        Group {
            if message.text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Analyzing...")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.AICardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
            } else {
                Text(LocalizedStringKey(message.text))
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.AICardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
            }
        }
    }
}

// MARK: - Main Chatbot View
struct ChatbotView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    private let sampleSuggestions = [
        "My Stock Outlook",
        "My portfolio Risks",
        "Recommended Stocks",
        "Why Did My Stock Move?"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.DarkPurpleAppBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !isChatting {
                        Spacer(minLength: 0)

                        headerText(isChatting: false)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)

                        suggestionPills
                            .padding(.bottom, 24)
                    } else {
                        HStack(spacing: 0) {
                            headerText(isChatting: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        messageList
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                                        .combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    inputBar
                }
                .animation(.spring(response: 0.85, dampingFraction: 0.88), value: viewModel.messages.isEmpty)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isChatting {
                        Button {
                            withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                                viewModel.resetSession()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var isChatting: Bool {
        !viewModel.messages.isEmpty
    }

    // MARK: - Header Text
    private func headerText(isChatting: Bool) -> some View {
        Text("What financial insights\ncan i give you today?")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .multilineTextAlignment(isChatting ? .leading : .center)
            .foregroundStyle(Color.white.opacity(isChatting ? 0.7 : 0.95))
            .lineSpacing(isChatting ? 1 : 4)
            .scaleEffect(isChatting ? 0.8 : 1.0, anchor: isChatting ? .leading : .center)
    }

    // MARK: - Suggestion Pills
    private var suggestionPills: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(sampleSuggestions, id: \.self) { suggestion in
                Button {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                        viewModel.send(suggestion)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.PrimaryYellow)
                        Text(suggestion)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.AICardBg)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
    }

    // MARK: - Message List
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("Ask anything...").foregroundColor(Color.white.opacity(0.4))
            )
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.AICardBg)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .focused($isInputFocused)
            .onSubmit {
                guard !isSendDisabled else { return }
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.send(viewModel.inputText)
                }
            }

            Button {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.send(viewModel.inputText)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isSendDisabled ? Color.white.opacity(0.2) : Color.PrimaryYellow)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }
}

#Preview {
    ChatbotView()
}
