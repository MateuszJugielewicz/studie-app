import SwiftUI

/// "Contact support": the user's requests to the Sonora team, answered from the admin dashboard.
struct SupportCenterView: View {
    @Environment(AppState.self) private var app
    /// Pre-fills a new request about this booking.
    var booking: Booking?

    @State private var tickets: [SupportTicket] = []
    @State private var isLoading = true
    @State private var isComposing = false
    @State private var error: String?

    private var active: [SupportTicket] { tickets.filter { $0.status != .closed } }
    private var closed: [SupportTicket] { tickets.filter { $0.status == .closed } }

    var body: some View {
        List {
            Section {
                Button { isComposing = true } label: {
                    HStack(spacing: 14) {
                        IconTile(symbol: "bubble.left.and.text.bubble.right.fill", size: 44, colors: TilePalette.signal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contact support").font(.headline).foregroundStyle(Color.primary)
                            Text("We usually reply within 24 hours.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.neon)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { ticket in
                        NavigationLink {
                            SupportTicketView(ticket: ticket) { updated in replace(updated) }
                        } label: {
                            SupportTicketRow(ticket: ticket)
                        }
                    }
                }
            } else if !isLoading {
                Section {
                    Text("Questions about a booking, a payment or your account? Send us a message and the EasySesh team will answer here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !closed.isEmpty {
                Section {
                    NavigationLink {
                        ClosedSupportTicketsView(tickets: closed) { updated in replace(updated) }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "archivebox.fill", colors: TilePalette.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Closed").foregroundStyle(Color.primary)
                                let unrated = closed.filter { $0.rating == nil }.count
                                if unrated > 0 {
                                    Text("\(unrated) waiting for your rating").font(.caption).foregroundStyle(Theme.accent)
                                }
                            }
                            Spacer()
                            Text("\(closed.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            Section {
                NavigationLink { LegalDocumentView(document: .refunds) } label: {
                    HStack { SettingsIcon(symbol: "arrow.uturn.backward.circle.fill", colors: TilePalette.ocean); Text("Refund & cancellation policy") }
                }
                NavigationLink { LegalListView() } label: {
                    HStack { SettingsIcon(symbol: "doc.text.fill", colors: TilePalette.muted); Text("Terms & privacy") }
                }
            } header: {
                Text("Policies")
            }
        }
        .sonoraGrouped()
        .navigationTitle("Help & support")
        .overlay { if isLoading && tickets.isEmpty { ProgressView() } }
        .refreshable { await Task { await load() }.value }
        .task { await load() }
        .sheet(isPresented: $isComposing) {
            NavigationStack {
                NewSupportTicketView(booking: booking) { ticket in
                    tickets.insert(ticket, at: 0)
                }
            }
        }
        .errorAlert($error)
    }

    private func load() async {
        defer { isLoading = false }
        do { tickets = try await app.backend.supportTickets() } catch { self.error = error.userMessage }
    }

    private func replace(_ ticket: SupportTicket) {
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) { tickets[index] = ticket }
    }
}

private struct SupportTicketRow: View {
    let ticket: SupportTicket

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ticket.category.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(ticket.subject).font(.subheadline.weight(ticket.userUnread > 0 ? .bold : .semibold)).lineLimit(1)
                    Spacer()
                    Text(ticket.lastMessageAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                }
                Text(ticket.lastMessagePreview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    StatusPill(text: ticket.status.title, color: ticket.status.color)
                    if ticket.userUnread > 0 {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityLabel("Unread reply")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension SupportTicketStatus {
    var color: Color {
        switch self {
        case .open: Theme.warning
        case .answered: Theme.positive
        case .closed: .secondary
        }
    }
}

struct NewSupportTicketView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var booking: Booking?
    var onCreated: (SupportTicket) -> Void

    @State private var category: SupportCategory = .other
    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var error: String?

    private var canSend: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
            && !isSending
    }

    var body: some View {
        Form {
            Section("What's it about?") {
                Picker("Topic", selection: $category) {
                    ForEach(availableCategories) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }
            if let booking {
                Section("Booking") {
                    InfoRow(symbol: "calendar", title: booking.reference, value: "\(booking.studioName) · \(booking.startsAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            Section {
                TextField("Subject", text: $subject)
                TextField("Describe what happened…", text: $message, axis: .vertical).lineLimit(6...14)
            } footer: {
                Text("Please don't share card numbers or passwords. The EasySesh team can see your account and bookings.")
            }
        }
        .sonoraGrouped()
        .navigationTitle("Contact support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSending ? "Sending…" : "Send") { send() }.disabled(!canSend)
            }
        }
        .onAppear {
            if let booking, subject.isEmpty {
                category = .booking
                subject = "Booking \(booking.reference)"
            }
        }
        .interactiveDismissDisabled(!message.isEmpty)
        .errorAlert($error)
    }

    private var availableCategories: [SupportCategory] {
        app.role == .studioOwner ? SupportCategory.allCases : SupportCategory.allCases.filter { $0 != .studio }
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let ticket = try await app.backend.createSupportTicket(subject: subject, category: category, body: message, bookingId: booking?.id)
                onCreated(ticket)
                dismiss()
            } catch { self.error = error.userMessage }
        }
    }
}

struct SupportTicketView: View {
    @Environment(AppState.self) private var app
    @State var ticket: SupportTicket
    var onChange: (SupportTicket) -> Void = { _ in }

    @State private var messages: [SupportMessage] = []
    @State private var draft = ""
    @State private var confirmClose = false
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    VStack(spacing: 6) {
                        Image(systemName: ticket.category.symbol).font(.title2).foregroundStyle(Theme.accent)
                        Text(ticket.subject).font(.headline).multilineTextAlignment(.center)
                        StatusPill(text: ticket.status.title, color: ticket.status.color)
                    }
                    .padding(.bottom, 8)

                    ForEach(messages) { message in
                        SupportBubble(message: message).id(message.id)
                    }

                    if ticket.status == .closed {
                        SupportRatingCard(ticket: $ticket, onChange: onChange)
                            .padding(.top, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Text("This request is closed. Send a message to reopen it.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { inputBar }
        .sonoraGrouped()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ticket.status != .closed {
                Menu {
                    Button("Mark as solved", systemImage: "checkmark.circle") { confirmClose = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Close this request?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Mark as solved") { close() }
        }
        .refreshable { await Task { await load() }.value }
        .task { await load() }
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
            messages = try await app.backend.supportMessages(ticketId: ticket.id)
            if ticket.userUnread > 0 {
                try await app.backend.markSupportTicketRead(id: ticket.id)
                ticket.userUnread = 0
                onChange(ticket)
            }
        } catch { self.error = error.userMessage }
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            do {
                let message = try await app.backend.sendSupportMessage(ticketId: ticket.id, body: text)
                messages.append(message)
                ticket.status = .open
                ticket.lastMessagePreview = String(message.body.prefix(140))
                ticket.lastMessageAt = message.createdAt
                onChange(ticket)
            } catch {
                draft = text
                self.error = error.userMessage
            }
        }
    }

    private func close() {
        Task {
            do {
                ticket = try await app.backend.closeSupportTicket(id: ticket.id)
                onChange(ticket)
            } catch { self.error = error.userMessage }
        }
    }
}

private struct SupportBubble: View {
    let message: SupportMessage

    var body: some View {
        HStack {
            if !message.fromAdmin { Spacer(minLength: 48) }
            VStack(alignment: message.fromAdmin ? .leading : .trailing, spacing: 3) {
                if message.fromAdmin {
                    HStack(spacing: 4) {
                        SonoraLogo(size: 11)
                        Text("support").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(message.body)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(message.fromAdmin ? AnyShapeStyle(Theme.card) : AnyShapeStyle(Theme.neon), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(message.fromAdmin ? Color.primary : Theme.onAccent)
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            if message.fromAdmin { Spacer(minLength: 48) }
        }
    }
}

/// The "Closed" folder: finished requests and their ratings.
struct ClosedSupportTicketsView: View {
    @State var tickets: [SupportTicket]
    var onChange: (SupportTicket) -> Void = { _ in }

    var body: some View {
        List {
            ForEach(tickets) { ticket in
                NavigationLink {
                    SupportTicketView(ticket: ticket) { updated in
                        if let index = tickets.firstIndex(where: { $0.id == updated.id }) { tickets[index] = updated }
                        onChange(updated)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        SupportTicketRow(ticket: ticket)
                        if let rating = ticket.rating {
                            StarsView(rating: rating, size: 12).padding(.leading, 40)
                        } else {
                            Label("Rate this request", systemImage: "star.bubble")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .sonoraGrouped()
        .navigationTitle("Closed")
    }
}

/// Read-only row of stars.
struct StarsView: View {
    let rating: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(star <= rating ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(rating) of 5 stars")
    }
}

/// Shown in a closed request: rate how support handled it.
struct SupportRatingCard: View {
    @Environment(AppState.self) private var app
    @Binding var ticket: SupportTicket
    var onChange: (SupportTicket) -> Void

    @State private var rating = 0
    @State private var comment = ""
    @State private var isEditing = false
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let given = ticket.rating, !isEditing {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thanks for your feedback!").font(.subheadline.weight(.bold))
                        StarsView(rating: given, size: 16)
                        if let text = ticket.ratingComment, !text.isEmpty {
                            Text("“\(text)”").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Edit") {
                        rating = given
                        comment = ticket.ratingComment ?? ""
                        withAnimation(.snappy) { isEditing = true }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("How did we do?").font(.headline)
                Text("Rate how the EasySesh team handled your request.").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { rating = star }
                        } label: {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(star <= rating ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                                .scaleEffect(star == rating ? 1.18 : 1)
                                .neonGlow(Theme.magenta, radius: 6, active: star <= rating)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) stars")
                    }
                }
                .frame(maxWidth: .infinity)
                .haptic(.selection, trigger: rating)
                TextField("Anything we could do better? (optional)", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(Theme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    send()
                } label: {
                    Text(isSending ? LocalizedStringKey("Sending…") : LocalizedStringKey("Send rating"))
                }
                .buttonStyle(.primary)
                .disabled(rating == 0 || isSending)
            }
        }
        .glassCard(padding: 16, cornerRadius: 22)
        .errorAlert($error)
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let updated = try await app.backend.rateSupportTicket(id: ticket.id, rating: rating, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    ticket = updated
                    isEditing = false
                }
                onChange(updated)
            } catch { self.error = error.userMessage }
        }
    }
}
