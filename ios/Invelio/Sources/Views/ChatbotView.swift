import SwiftUI

// MARK: - Message Model
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
    let isFinished: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        isFinished: Bool = true,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.isFinished = isFinished
        self.timestamp = timestamp
    }
}

// MARK: - View Model
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isProcessing: Bool = false

    private var sessionId = UUID()
    private var streamTask: Task<Void, Never>?

    func send(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }

        let userMessage = ChatMessage(text: trimmed, isUser: true, isFinished: true)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        let botMessageId = UUID()
        messages.append(ChatMessage(id: botMessageId, text: "", isUser: false, isFinished: false))

        streamTask = Task {
            await streamFromAgent(query: trimmed, botMessageId: botMessageId)
        }
    }

    private func streamFromAgent(query: String, botMessageId: UUID) async {
        var accumulated = ""
        let stream = APIClient.shared.chatStream(
            message: query,
            sessionId: sessionId
        )

        do {
            for try await chunk in stream {
                accumulated += chunk
                updateBotMessage(id: botMessageId, text: accumulated, isFinished: false)
            }
        } catch {
            print("[ChatBot] Stream error: \(error)")
            if accumulated.isEmpty {
                accumulated = "Error: \(error.localizedDescription)"
            }
        }
        withAnimation(.easeOut(duration: 0.3)) {
            updateBotMessage(id: botMessageId, text: accumulated, isFinished: true)
        }
        isProcessing = false
    }

    private func updateBotMessage(id: UUID, text: String, isFinished: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage(id: id, text: text, isUser: false, isFinished: isFinished)
    }

    func resetSession() {
        streamTask?.cancel()
        messages.removeAll()
        inputText = ""
        isProcessing = false
        sessionId = UUID()
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
                VStack(alignment: .leading, spacing: 10) {
                    // Message Content
                    Text(LocalizedStringKey(message.text))
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(4)

                    if message.isFinished {
                        // Source Indicator
                        HStack(spacing: 5) {
                            Text("Source:")
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))

                            HStack(spacing: 4.5) {
                                Image("sectors_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                                Text("Sectors")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        // AI Disclaimer Banner (Under Source, Yellow with opacity, icon aligned with text start)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.PrimaryYellow.opacity(0.9))
                                .padding(.top, 1.5)
                            Text("Disclaimer: AI-generated content. For informational purposes only. Not financial or investment advice.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.PrimaryYellow.opacity(0.85))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.PrimaryYellow.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.PrimaryYellow.opacity(0.25), lineWidth: 0.8)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                    }

                VStack(spacing: 0) {
                    if !isChatting {
                        Spacer(minLength: 0)

                        headerText(isChatting: false)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)

                        suggestionPills
                            .padding(.bottom, 24)
                    } else {
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
            .simultaneousGesture(
                TapGesture().onEnded {
                    isInputFocused = false
                }
            )
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
                    HStack(spacing: 0) {
                        headerText(isChatting: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
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
