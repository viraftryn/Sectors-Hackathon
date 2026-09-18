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

            • **Overall Trend:** Bullish pada sektor perbankan dan konsumer defensif.
            • **Top Movers:** BBCA (+0.77%), BMRI (+0.78%), DCII (+2.04%).
            • **Key Catalyst:** Laporan laba kuartalan yang melampaui konsensus pasar serta stabilitas nilai tukar Rupiah.

            **Strategic Action:**
            Pertahankan posisi (Hold) pada big-cap leaders dan lakukan akumulasi bertahap saat retrace ke level support terdekat.
            """
        } else if q.contains("RISK") || q.contains("PORTFOLIO") {
            return """
            **Portfolio Risk Assessment**

            • **Tingkat Risiko:** Moderat
            • **Konsentrasi Sektor:** 65% Financials, 20% Technology, 15% Energy
            • **Volatilitas 30-Hari (Beta):** 0.92 (di bawah volatilitas IHSG)

            **Potensi Risiko & Mitigasi:**
            1. **Sektor Energy (BYAN):** Terpapar penurunan harga komoditas global. Disarankan rebalancing berkala.
            2. **Diversifikasi:** Pertimbangkan menambah porsi pada sektor Consumer Non-Cyclicals atau Healthcare untuk meredam fluktuasi jangka pendek.
            """
        } else if q.contains("RECOMMENDED") || q.contains("REKOMENDASI") {
            return """
            **Recommended Stocks (Pilihan Teratas)**

            1. **BBCA (Bank Central Asia)**
               • Target Harga: Rp 10.500 | Rating: BUY
               • Katalis: Margin bunga bersih solid & pertumbuhan kredit konsisten.

            2. **DCII (DCI Indonesia)**
               • Target Harga: Rp 46.000 | Rating: STRONG BUY
               • Katalis: Ledakan adopsi AI dan ekspansi kapasitas hyperscale data center.

            3. **BMRI (Bank Mandiri)**
               • Target Harga: Rp 7.100 | Rating: ACCUMULATE
               • Katalis: Efisiensi digital Livin' dan dividen yield menarik (>5%).
            """
        } else if q.contains("MOVE") || q.contains("WHY") {
            return """
            **Kenapa Saham Anda Bergerak Hari Ini?**

            • **Sentimen Pasar Positif:** IHSG menguat didorong inflow asing sebesar Rp 450 miliar pada sektor finansial.
            • **BBCA & BMRI:** Bergerak naik seiring penguatan likuiditas perbankan dan proyeksi NIM yang tetap ekspansif.
            • **DCII (+2.04%):** Katalis permintaan komputasi awan dan sentimen investasi AI regional.
            • **BYAN (-0.86%):** Tertekan aksi profit taking akibat koreksi harga batubara Newcastle.
            """
        } else if q.contains("BBCA") || q.contains("BCA") {
            return """
            **Analisis PT Bank Central Asia Tbk (BBCA)**

            • **Rekomendasi:** BUY / ACCUMULATE
            • **Konsensus Target Harga:** Rp 11.250 (+12,5%)
            • **Valuasi Saat Ini:** PER 22,4x | PBV 4,8x | ROE 23,1%
            • **Dividend Yield:** ~3,1% p.a.

            **Poin Kunci:**
            1. Kualitas aset paling solid di industri perbankan dengan CASA ratio di atas 80%.
            2. Pertumbuhan kredit konsisten 13-14% YoY didorong segmen komersial dan konsumer.
            3. Sentimen suku bunga BI yang stabil memberikan ruang bagi pertumbuhan margin bunga bersih (NIM).

            *Kesimpulan: Cocok untuk investasi jangka menengah-panjang dengan profil risiko konservatif.*
            """
        } else if q.contains("ASII") || q.contains("ASTRA") {
            return """
            **Analisis PT Astra International Tbk (ASII)**

            • **Rekomendasi:** NEUTRAL / HOLD
            • **Target Harga:** Rp 5.600 (+6,2%)
            • **Valuasi Saat Ini:** PER 6,8x | PBV 0,9x (Undervalued)
            • **Dividend Yield:** Sangat Menarik (~7,8% p.a.)

            **Katalog Risiko & Peluang:**
            • Tekanan dari persaingan kendaraan listrik (EV) merek baru di Indonesia.
            • Namun, diversifikasi di sektor alat berat (UNTR) dan agribisnis memberikan bantalan arus kas kuat.
            • Dividend payout ratio tetap konsisten tinggi di atas 50%.
            """
        } else if q.contains("TLKM") || q.contains("TELKOM") {
            return """
            **Analisis PT Telkom Indonesia Tbk (TLKM)**

            • **Rekomendasi:** BUY
            • **Target Harga:** Rp 3.450 (+15,0%)
            • **Valuasi Saat Ini:** PER 14,2x | PBV 2,3x | Dividend Yield ~4,8%

            **Sentimen Utama:**
            1. Integrasi IndiHome ke Telkomsel (FMC) meningkatkan efisiensi operasional dan ARPU.
            2. Monetisasi bisnis Data Center melalui NeutraDC berpotensi unlock value signifikan di 2026.
            """
        } else if q.contains("DIVIDEN") || q.contains("DIVIDEND") {
            return """
            **Top Saham Dividen Tinggi IHSG (High Dividend Yield)**

            1. **ASII** - Yield est. 7,8% | Payout ~50%
            2. **PTBA** - Yield est. 11,2% | Payout ~75%
            3. **ITMG** - Yield est. 12,5% | Payout ~65%
            4. **BMRI** - Yield est. 5,1% | Payout ~60%
            5. **BBRI** - Yield est. 5,4% | Payout ~70%

            *Tips: Perhatikan jadwal Cum Date dan pastikan fundamental kas operasional emiten tetap sehat.*
            """
        } else {
            return """
            **Analisis Ringkas Pasar Saham**

            Pertanyaan Anda mengenai: *"\(query)"*

            • **Sentimen Pasar:** Net foreign inflow terpantau positif pada sektor perbankan dan telekomunikasi.
            • **Valuasi IHSG:** P/E rata-rata IHSG berada di kisaran 13,8x, berada di bawah rata-rata historis 5 tahun (tergolong menarik).
            • **Katalis Utama:** Stabilitas nilai tukar Rupiah, inflasi domestik yang terjaga, serta rilis kinerja keuangan emiten Q2.

            *💡 Anda juga dapat menanyakan ticker saham spesifik seperti BBCA, ASII, TLKM, atau rekomendasi dividen.*
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
                    Text("Menganalisis...")
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
