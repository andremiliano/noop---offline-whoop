import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach as a conversation: your messages on the right, the coach's on the left, a box to type in at the
/// bottom, and questions to tap above it. Nothing else on the screen.
///
/// It drives the same `AICoachEngine` as the original `CoachView` (which still owns provider and key
/// setup), so the saved conversation, consent, fallback and the master switch behave identically.
struct CoachChatView: View {
    @EnvironmentObject var coach: AICoachEngine
    @EnvironmentObject var repo: Repository

    let onDone: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var showConnection = false
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(StrandPalette.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if coach.messages.isEmpty && !coach.sending { welcome }
                        ForEach(coach.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if coach.sending && (coach.messages.last?.text.isEmpty ?? true) { typing }
                        if let note = coach.fallbackNote { notice(note, icon: "iphone") }
                        if let error = coach.errorText, !error.isEmpty { errorRow(error) }
                        Color.clear.frame(height: 1).id(Self.bottom)
                    }
                    .padding(.horizontal, NoopMetrics.space4)
                    .padding(.vertical, NoopMetrics.space3)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChangeCompat(of: coach.messages.count) { _ in scrollToEnd(proxy) }
                .onChangeCompat(of: coach.messages.last?.text) { _ in scrollToEnd(proxy, animated: false) }
                .onChangeCompat(of: coach.sending) { _ in scrollToEnd(proxy) }
                .task { scrollToEnd(proxy, animated: false) }
            }
            Divider().overlay(StrandPalette.hairline)
            if !coach.messages.isEmpty { chips }
            composer
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            coach.retireStaleConversationIfNeeded()
        }
        // A question handed over by the Today launcher: sent once, cleared first.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            await coach.send(prompt)
        }
        .sheet(isPresented: $showConnection) {
            NavigationStack {
                CoachView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showConnection = false }
                        }
                    }
            }
            .environmentObject(coach)
            .environmentObject(repo)
        }
        .confirmationDialog("Clear conversation?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { coach.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved conversation from this device. Coach history is your own notes, not medical advice.")
        }
    }

    private static let bottom = "chat-bottom"

    // MARK: Header

    private var header: some View {
        HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Coach")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: coach.provider == .onDevice ? String(localized: "On this device")
                     : coach.provider.displayName)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Menu {
                Button { showConnection = true } label: {
                    Label("Connection and key", systemImage: "key.fill")
                }
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Clear conversation", systemImage: "trash")
                }
                .disabled(coach.messages.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .accessibilityLabel(String(localized: "Coach options"))
            Button("Done", action: onDone)
                .font(StrandFont.subhead.weight(.semibold))
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, NoopMetrics.space3)
    }

    // MARK: Empty state: questions to tap

    private var welcome: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("What do you want to know?")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Tap a question, or type your own below.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            ForEach(Self.dedup(coach.suggestions + Self.starters), id: \.self) { q in
                Button { send(q) } label: {
                    HStack {
                        Text(verbatim: q)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(StrandPalette.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                }
                .buttonStyle(LiquidPressStyle())
                .disabled(coach.sending)
            }
        }
        .padding(.top, NoopMetrics.space2)
    }

    /// Questions that make sense for anyone with a wearer's data, after the ones drawn from today's numbers.
    static let starters = [
        "How did I sleep last night?",
        "Should I train hard today?",
        "Why is my HRV what it is?",
        "What should I do this week?",
    ]

    static func dedup(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }.prefix(6).map { $0 }
    }

    // MARK: Messages

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(verbatim: message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("You said: \(message.text)"))
        case .assistant:
            if !message.text.isEmpty {
                HStack {
                    Markdown(message.text)
                        .markdownTheme(.strand)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.text, forType: .string)
                                #else
                                UIPasteboard.general.string = message.text
                                #endif
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                            ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    Spacer(minLength: 40)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Coach said: \(message.text)"))
            }
        }
    }

    private var typing: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label { Text(verbatim: text).font(StrandFont.caption) } icon: { Image(systemName: icon) }
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(verbatim: text).font(StrandFont.subhead) } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(StrandPalette.statusCritical)
            .fixedSize(horizontal: false, vertical: true)
            if coach.keyRejected {
                Button("Fix the key") { showConnection = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Chips + composer

    /// Quick questions above the box once a conversation is going: the follow-ups first, then today's.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.dedup(AICoachEngine.followUpSuggestions + coach.suggestions), id: \.self) { q in
                    Button { send(q) } label: {
                        Text(verbatim: q)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(LiquidPressStyle())
                    .disabled(coach.sending)
                }
            }
            .padding(.horizontal, NoopMetrics.space4)
            .padding(.vertical, 8)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything about your data…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(focused ? StrandPalette.focusRing : StrandPalette.hairline, lineWidth: 1))
                .onSubmit { send(draft) }
                .submitLabel(.send)
                .accessibilityLabel(Text("Question"))
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? StrandPalette.accent : StrandPalette.textTertiary))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, NoopMetrics.space3)
    }

    private var canSend: Bool {
        !coach.sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !coach.sending else { return }
        draft = ""
        focused = false
        Task { await coach.send(q) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottom, anchor: .bottom)
        }
    }
}
