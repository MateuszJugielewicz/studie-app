import SwiftUI

struct ConversationsView: View {
    @Environment(AppState.self) private var app
    @State private var conversations: [Conversation] = []
    @State private var path = NavigationPath()
    @State private var isLoading = true

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if conversations.isEmpty && !isLoading {
                    ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text(app.role == .artist
                        ? "Message a studio from its profile or from one of your bookings."
                        : "Artists can message you about your studio and their bookings."))
                }
                ForEach(conversations) { conversation in
                    NavigationLink(value: conversation) {
                        ConversationRow(conversation: conversation, role: app.role)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Messages")
            .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: path.count) { if path.isEmpty { Task { await load() } } }
            .onChange(of: app.pendingDeepLink) { openDeepLink() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        conversations = (try? await app.backend.conversations()) ?? conversations
        app.unreadMessages = conversations.reduce(0) { $0 + $1.unread(for: app.role) }
        openDeepLink()
    }

    private func openDeepLink() {
        guard case .conversation(let id) = app.consumeDeepLink({ if case .conversation = $0 { return true }; return false }) else { return }
        if let conversation = conversations.first(where: { $0.id == id }) { path.append(conversation) }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let role: UserRole

    var body: some View {
        HStack(spacing: 12) {
            if role == .artist {
                RemoteImage(url: conversation.studioPhotoUrl).frame(width: 48, height: 48).clipShape(Circle())
            } else {
                Avatar(url: nil, name: conversation.artistName, size: 48)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title(for: role)).font(.headline)
                    Spacer()
                    Text(conversation.lastMessageAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if conversation.bookingId != nil {
                        Image(systemName: "calendar").font(.caption).foregroundStyle(Theme.accent)
                    }
                    Text(conversation.lastMessagePreview.isEmpty ? "New conversation" : conversation.lastMessagePreview)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    let unread = conversation.unread(for: role)
                    if unread > 0 {
                        Text("\(unread)").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2).background(Theme.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChatView: View {
    @Environment(AppState.self) private var app
    let conversation: Conversation

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var reporting: ChatMessage?
    @State private var booking: Booking?
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let booking {
                        NavigationLink {
                            BookingDetailView(bookingId: booking.id, initial: booking)
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text("\(booking.sessionTypeName) · \(booking.startsAt.formatted(date: .abbreviated, time: .shortened))")
                                Spacer()
                                StatusPill(text: booking.status.title, color: booking.status.color)
                            }
                            .font(.footnote)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Keep payments and bookings inside Sonora – you're protected by our refund policy.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.bottom, 8)

                    ForEach(messages) { message in
                        MessageBubble(message: message, isMine: message.senderId == app.account?.id)
                            .id(message.id)
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
                                if message.senderId != nil && message.senderId != app.account?.id {
                                    Button("Report message", systemImage: "flag") { reporting = message }
                                }
                            }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle(conversation.title(for: app.role))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reporting) { ReportSheet(target: .message, targetId: $0.id) }
        .task { await load() }
        .task { await listen() }
        .errorAlert($error)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(Theme.neon).neonGlow(Theme.magenta, radius: 8)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func load() async {
        do {
            messages = try await app.backend.messages(conversationId: conversation.id)
            try await app.backend.markConversationRead(id: conversation.id)
            if let bookingId = conversation.bookingId { booking = try? await app.backend.booking(id: bookingId) }
        } catch { self.error = error.userMessage }
    }

    private func listen() async {
        for await message in app.backend.messageStream(conversationId: conversation.id) {
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            try? await app.backend.markConversationRead(id: conversation.id)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            do {
                let message = try await app.backend.sendMessage(conversationId: conversation.id, body: text)
                if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            } catch {
                draft = text
                self.error = error.userMessage
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        if message.kind != .text {
            Label(message.body, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack {
                if isMine { Spacer(minLength: 48) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                    Text(message.body)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(isMine ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Theme.card), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .foregroundStyle(isMine ? Theme.onAccent : Color.primary)
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
                if !isMine { Spacer(minLength: 48) }
            }
        }
    }
}

struct NotificationsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if app.notifications.isEmpty {
                    ContentUnavailableView("You're all caught up", systemImage: "bell.slash")
                }
                ForEach(app.notifications) { note in
                    Button {
                        Task { await app.markNotificationRead(note) }
                        if let link = link(for: note) { app.open(link) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: note.kind.symbol)
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title).font(.subheadline.weight(note.isRead ? .regular : .bold))
                                Text(note.body).font(.subheadline).foregroundStyle(.secondary)
                                Text(note.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if !note.isRead { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notifications")
            .toolbar {
                if app.unreadNotifications > 0 {
                    Button("Mark all read") { Task { await app.markAllNotificationsRead() } }
                }
            }
            .refreshable { await app.refreshBadges() }
            .task { await app.refreshBadges() }
        }
    }

    private func link(for note: AppNotification) -> DeepLink? {
        if let id = note.conversationId { return .conversation(id) }
        if let id = note.bookingId { return .booking(id) }
        if let id = note.studioId { return .studio(id) }
        return nil
    }
}
