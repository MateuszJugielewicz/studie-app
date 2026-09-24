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

    var body: some View {
        List {
            Section {
                Button { isComposing = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contact support").font(.headline).foregroundStyle(Color.primary)
                            Text("We usually reply within 24 hours.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !tickets.isEmpty {
                Section("Your requests") {
                    ForEach(tickets) { ticket in
                        NavigationLink {
                            SupportTicketView(ticket: ticket) { updated in replace(updated) }
                        } label: {
                            SupportTicketRow(ticket: ticket)
                        }
                    }
                }
            } else if !isLoading {
                Section {
                    Text("Questions about a booking, a payment or your account? Send us a message and the Sonora team will answer here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink { LegalDocumentView(document: .refunds) } label: { Label("Refund & cancellation policy", systemImage: "arrow.uturn.backward.circle") }
                NavigationLink { LegalListView() } label: { Label("Terms & privacy", systemImage: "doc.text") }
            } header: {
                Text("Policies")
            }
        }
        .navigationTitle("Help & support")
        .overlay { if isLoading && tickets.isEmpty { ProgressView() } }
        .refreshable { await load() }
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
                Text("Please don't share card numbers or passwords. The Sonora team can see your account and bookings.")
            }
        }
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
                        Text("This request is closed. Send a message to reopen it.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
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
        .refreshable { await load() }
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
