import SwiftUI

enum ConversationFilter: String, CaseIterable, Identifiable {
    case all, unread, requests
    var id: String { rawValue }

    func title(for role: UserRole) -> String {
        switch self {
        case .all: L10n.tr("All")
        case .unread: L10n.tr("Unread")
        case .requests: role == .artist ? L10n.tr("Requests") : L10n.tr("Sent requests")
        }
    }
}

struct ConversationsView: View {
    @Environment(AppState.self) private var app
    @State private var conversations: [Conversation] = []
    @State private var path = NavigationPath()
    @State private var isLoading = true
    @State private var filter: ConversationFilter = .all
    @State private var isComposing = false
    @State private var error: String?

    private var requests: [Conversation] { conversations.filter(\.isPendingRequest) }

    private var visible: [Conversation] {
        switch filter {
        case .all:
            // Artists see pending requests only in the Requests folder; declined threads are hidden.
            app.role == .artist ? conversations.filter { $0.status == .accepted } : conversations
        case .unread:
            conversations.filter { $0.badgeCount(for: app.role) > 0 }
        case .requests:
            requests
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            EasySeshScreen("Messages", eyebrow: eyebrow, refresh: { await load() }) {
                if app.role == .studioOwner && app.ownedStudio?.status == .approved {
                    GlassIconButton(symbol: "square.and.pencil", label: "New message") { isComposing = true }
                }
            } content: {
                filterChips
                if app.role == .artist && filter == .all && !requests.isEmpty {
                    requestsBanner
                }
                if visible.isEmpty && !isLoading {
                    GlassEmptyState(title: emptyTitle, symbol: filter == .requests ? "tray" : "bubble.left.and.bubble.right.fill", message: emptyMessage)
                }
                LazyVStack(spacing: 10) {
                    ForEach(visible) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRow(conversation: conversation, role: app.role)
                        }
                        .buttonStyle(PressableCardStyle())
                        .scrollReveal()
                        .contextMenu {
                            if app.role == .artist && conversation.isPendingRequest {
                                Button("Accept", systemImage: "checkmark") { respond(conversation, accept: true) }
                                Button("Delete request", systemImage: "trash", role: .destructive) { respond(conversation, accept: false) }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
            .sheet(isPresented: $isComposing) {
                NavigationStack {
                    NewMessageSheet { conversation in
                        conversations.removeAll { $0.id == conversation.id }
                        conversations.insert(conversation, at: 0)
                        path.append(conversation)
                    }
                }
            }
            .task { await load() }
            .onChange(of: path.count) { if path.isEmpty { Task { await load() } } }
            .onChange(of: app.pendingDeepLink) { openDeepLink() }
            .errorAlert($error)
        }
    }

    private var eyebrow: String {
        let unread = conversations.reduce(0) { $0 + $1.badgeCount(for: app.role) }
        return unread > 0 ? L10n.format("%lld unread", unread) : L10n.tr("Inbox")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConversationFilter.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { filter = item }
                    } label: {
                        HStack(spacing: 6) {
                            Chip(title: item.title(for: app.role), isSelected: filter == item)
                        }
                        .overlay(alignment: .topTrailing) {
                            if item == .requests && !requests.isEmpty {
                                Text("\(requests.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Theme.accent, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .haptic(.selection, trigger: filter)
    }

    private var requestsBanner: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { filter = .requests }
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "tray.full.fill", size: 36, colors: TilePalette.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Message requests").font(.subheadline.weight(.bold))
                    Text(requests.count == 1 ? L10n.tr("1 studio wants to talk to you") : L10n.format("%lld studios want to talk to you", requests.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .glassCard(padding: 12)
        }
        .buttonStyle(PressableCardStyle())
    }

    private var emptyTitle: String {
        switch filter {
        case .all: L10n.tr("No messages yet")
        case .unread: L10n.tr("You're all caught up")
        case .requests: app.role == .artist ? L10n.tr("No message requests") : L10n.tr("No pending requests")
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .requests:
            app.role == .artist
                ? L10n.tr("When a studio you haven't booked writes to you, it shows up here first.")
                : L10n.tr("Artists you message who haven't booked you yet see it as a request until they accept.")
        default:
            app.role == .artist
                ? L10n.tr("Message a studio from its profile or from one of your bookings.")
                : L10n.tr("Artists can message you about your studio and bookings. Tap ✎ to write to an artist.")
        }
    }

    private func load() async {
        defer { isLoading = false }
        conversations = (try? await app.backend.conversations()) ?? conversations
        app.unreadMessages = conversations.reduce(0) { $0 + $1.badgeCount(for: app.role) }
        openDeepLink()
    }

    private func respond(_ conversation: Conversation, accept: Bool) {
        Task {
            do {
                let updated = try await app.backend.respondToMessageRequest(conversationId: conversation.id, accept: accept)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if let index = conversations.firstIndex(where: { $0.id == updated.id }) { conversations[index] = updated }
                }
            } catch { self.error = error.userMessage }
        }
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
        let unread = conversation.unread(for: role)
        HStack(spacing: 12) {
            ZStack {
                if role == .artist {
                    RemoteImage(url: conversation.studioPhotoUrl).frame(width: 52, height: 52).clipShape(Circle())
                } else {
                    Avatar(url: conversation.artistAvatarUrl, name: conversation.artistName, size: 52)
                }
            }
            .padding(2.5)
            .overlay {
                Circle().strokeBorder(unread > 0 ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: 2.5)
            }
            .neonGlow(Theme.magenta, radius: 8, active: unread > 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title(for: role)).font(.headline.weight(unread > 0 ? .heavy : .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.lastMessageAt.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(unread > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }
                HStack(spacing: 6) {
                    if conversation.isPendingRequest {
                        tag(role == .artist ? "Request" : "Request sent", symbol: "tray")
                    } else if conversation.isDeclined && role == .studioOwner {
                        tag("Declined", symbol: "hand.raised")
                    } else if conversation.bookingId != nil {
                        Image(systemName: "calendar").font(.caption).foregroundStyle(Theme.accent)
                    }
                    Text(conversation.lastMessagePreview.isEmpty ? "New conversation" : conversation.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(unread > 0 ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.neon, in: Capsule())
                    }
                }
            }
        }
        .glassCard(padding: 12)
    }

    private func tag(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.violet.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.violet)
    }
}

/// Studio → artist: pick an artist (search, or someone who booked you) and write the first message.
struct NewMessageSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onSent: (Conversation) -> Void

    @State private var query = ""
    @State private var results: [ArtistSearchResult] = []
    @State private var selected: ArtistSearchResult?
    @State private var message = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        Group {
            if let selected {
                compose(selected)
            } else {
                picker
            }
        }
        .easyseshGrouped()
        .navigationTitle(selected == nil ? "New message" : selected!.artistName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LocalizedStringKey(selected == nil ? "Cancel" : "Back")) {
                    if selected == nil { dismiss() } else { withAnimation(.snappy) { selected = nil } }
                }
            }
            if selected != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(isSending ? "Sending…" : "Send")) { send() }
                        .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .errorAlert($error)
    }

    private var picker: some View {
        List {
            Section {
                if results.isEmpty {
                    Text(LocalizedStringKey(query.count < 2 ? "Artists who booked you appear here. Search to find others by name or city." : "No artists found."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(results) { artist in
                    Button {
                        withAnimation(.snappy) { selected = artist }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(url: artist.avatarUrl, name: artist.artistName, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(artist.artistName).font(.headline).foregroundStyle(.primary)
                                    if artist.isVerified { VerifiedBadge() }
                                    if artist.hasAdminBadge == true { AdminBadge(compact: true) }
                                }
                                Text([artist.city, artist.genres.prefix(2).joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if artist.hasBooked {
                                Text("Booked you").font(.caption2.weight(.bold)).foregroundStyle(Theme.positive)
                            }
                        }
                    }
                }
            } header: {
                Text(LocalizedStringKey(query.count < 2 ? "Your artists" : "Artists"))
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search artists")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            do { results = try await app.backend.searchArtists(query: query) } catch { self.error = error.userMessage }
        }
    }

    private func compose(_ artist: ArtistSearchResult) -> some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Avatar(url: artist.avatarUrl, name: artist.artistName, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.artistName).font(.headline)
                        Text(LocalizedStringKey(artist.hasBooked ? "Goes straight to their inbox." : "They'll get it as a message request and can accept or delete it."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField("Write a message…", text: $message, axis: .vertical).lineLimit(5...12)
            } footer: {
                Text("Be personal and relevant. Studios that spam artists can be suspended.")
            }
        }
    }

    private func send() {
        guard let selected else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let conversation = try await app.backend.startConversation(artistId: selected.id, body: message)
                dismiss()
                onSent(conversation)
            } catch { self.error = error.userMessage }
        }
    }
}

struct ChatView: View {
    @Environment(AppState.self) private var app
    @State var conversation: Conversation

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
                    Text("Keep payments and bookings inside EasySesh – you're protected by our refund policy.")
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
        .safeAreaInset(edge: .bottom) { bottomBar }
        .easyseshGrouped()
        .navigationTitle(conversation.title(for: app.role))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Tap the name to see who you're talking to.
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    if app.role == .studioOwner {
                        ArtistPublicProfileView(artistId: conversation.artistId, initial: nil)
                    } else {
                        StudioDetailView(studioId: conversation.studioId, initial: nil)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Avatar(url: app.role == .studioOwner ? conversation.artistAvatarUrl : conversation.studioPhotoUrl,
                               name: conversation.title(for: app.role), size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(conversation.title(for: app.role)).font(.subheadline.weight(.bold)).lineLimit(1)
                            Text(LocalizedStringKey(app.role == .studioOwner ? "View artist profile" : "View studio"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text(LocalizedStringKey(app.role == .studioOwner ? "View artist profile" : "View studio")))
            }
        }
        .sheet(item: $reporting) { ReportSheet(target: .message, targetId: $0.id) }
        .task { await load() }
        .task { await listen() }
        .errorAlert($error)
    }

    @ViewBuilder private var bottomBar: some View {
        if app.role == .artist && conversation.isPendingRequest {
            requestBar
        } else if app.role == .studioOwner && conversation.isDeclined {
            Label("This artist isn't accepting messages from your studio.", systemImage: "hand.raised.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
        } else {
            inputBar
        }
    }

    /// Instagram-style request: accept to reply, or delete. Replying also accepts.
    private var requestBar: some View {
        VStack(spacing: 10) {
            Text("\(conversation.studioName) wants to send you a message")
                .font(.subheadline.weight(.semibold))
            Text("Accept to reply. They won't know you've seen it until you do.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Delete", role: .destructive) { respond(accept: false) }
                    .buttonStyle(.secondary)
                Button("Accept") { respond(accept: true) }
                    .buttonStyle(.primary)
            }
        }
        .padding()
        .background(.bar)
    }

    private func respond(accept: Bool) {
        Task {
            do {
                let updated = try await app.backend.respondToMessageRequest(conversationId: conversation.id, accept: accept)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { conversation = updated }
            } catch { self.error = error.userMessage }
        }
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
    @State private var confirmClear = false

    var body: some View {
        let fresh = app.notifications.filter { !$0.isRead }
        let earlier = app.notifications.filter(\.isRead)
        NavigationStack {
            EasySeshScreen("Inbox", eyebrow: fresh.isEmpty ? L10n.tr("Notifications") : L10n.format("%lld new", fresh.count), refresh: { await app.refreshBadges() }) {
                HStack(spacing: 8) {
                    if !fresh.isEmpty {
                        GlassIconButton(symbol: "checkmark.circle", label: "Mark all read") {
                            Task { await app.markAllNotificationsRead() }
                        }
                    }
                    if !app.notifications.isEmpty {
                        GlassIconButton(symbol: "trash", label: "Clear all") { confirmClear = true }
                    }
                }
            } content: {
                if app.notifications.isEmpty {
                    GlassEmptyState(title: "You're all caught up", symbol: "bell.badge.fill", message: "Bookings, messages and payouts show up here.")
                }
                if !fresh.isEmpty {
                    GlowSectionHeader(title: "New", count: fresh.count)
                    ForEach(fresh) { note in row(note) }
                }
                if !earlier.isEmpty {
                    GlowSectionHeader(title: "Earlier")
                    ForEach(earlier) { note in row(note) }
                }
                if !app.notifications.isEmpty {
                    Label("Swipe left on a notification to delete it", systemImage: "hand.draw")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: app.notifications)
            .task { await app.refreshBadges() }
            .confirmationDialog("Delete all notifications?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { Task { await app.deleteAllNotifications() } }
            }
        }
    }

    private func row(_ note: AppNotification) -> some View {
        Button {
            Task { await app.markNotificationRead(note) }
            if let link = link(for: note) { app.open(link) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: note.kind.symbol, size: 40, colors: note.isRead ? TilePalette.muted : palette(for: note.kind))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(localized: note.title).font(.subheadline.weight(note.isRead ? .semibold : .heavy)).lineLimit(2)
                        Spacer(minLength: 6)
                        Text(note.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14)
            .overlay(alignment: .topTrailing) {
                if !note.isRead {
                    Circle().fill(Theme.neon).frame(width: 9, height: 9).neonGlow(Theme.magenta, radius: 5).offset(x: -8, y: 8)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .swipeToDelete { Task { await app.deleteNotification(note) } }
        .scrollReveal()
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func palette(for kind: NotificationKind) -> [Color] {
        switch kind {
        case .bookingConfirmed, .studioApproved, .payoutSent: TilePalette.mint
        case .bookingCancelled, .bookingDeclined, .studioRejected, .refundIssued: [Color.red, Theme.magenta]
        case .newMessage: TilePalette.ocean
        case .newReview, .reviewReminder: [Theme.warning, Theme.accent]
        default: TilePalette.signal
        }
    }

    private func link(for note: AppNotification) -> DeepLink? {
        if let id = note.conversationId { return .conversation(id) }
        if let id = note.bookingId { return .booking(id) }
        if let id = note.studioId { return .studio(id) }
        return nil
    }
}
