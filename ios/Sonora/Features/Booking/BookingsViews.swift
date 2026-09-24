import SwiftUI

struct ArtistBookingsView: View {
    @Environment(AppState.self) private var app
    @State private var bookings: [Booking] = []
    @State private var mode = Mode.upcoming
    @State private var selectedDay = Date.now.startOfDay
    @State private var path = NavigationPath()
    @State private var isLoading = true
    @State private var reviewing: Booking?

    enum Mode: String, CaseIterable { case upcoming = "Upcoming", calendar = "Calendar", past = "Past" }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch mode {
                case .upcoming:
                    let upcoming = bookings.filter { $0.isUpcoming }.sorted { $0.startsAt < $1.startsAt }
                    if upcoming.isEmpty && !isLoading {
                        ContentUnavailableView("No upcoming sessions", systemImage: "calendar", description: Text("Find a studio and book your next session."))
                    }
                    ForEach(upcoming) { row($0) }
                case .calendar:
                    MonthCalendar(selectedDay: $selectedDay, markedDays: Set(bookings.filter { !$0.status.isClosed || $0.status == .completed }.map { $0.startsAt.startOfDay }))
                        .listRowBackground(Color.clear)
                    let dayBookings = bookings.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: selectedDay) }
                    if dayBookings.isEmpty {
                        Text("Nothing booked on \(selectedDay.formatted(date: .abbreviated, time: .omitted)).").foregroundStyle(.secondary)
                    }
                    ForEach(dayBookings) { row($0) }
                case .past:
                    let toReview = bookings.filter(\.canReview)
                    if !toReview.isEmpty {
                        Section("Waiting for your review") {
                            ForEach(toReview) { booking in
                                Button { reviewing = booking } label: {
                                    Label("Review \(booking.studioName)", systemImage: "star.bubble")
                                }
                            }
                        }
                    }
                    Section("History") {
                        ForEach(bookings.filter { !$0.isUpcoming }) { row($0) }
                    }
                }
            }
            .navigationTitle("Bookings")
            .navigationDestination(for: Booking.self) { BookingDetailView(bookingId: $0.id, initial: $0) }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: app.pendingDeepLink) { openDeepLink() }
            .sheet(item: $reviewing) { booking in
                WriteReviewView(booking: booking) { Task { await load() } }
            }
        }
    }

    private func row(_ booking: Booking) -> some View {
        NavigationLink(value: booking) { BookingRow(booking: booking, perspective: .artist) }
    }

    private func load() async {
        defer { isLoading = false }
        bookings = (try? await app.backend.artistBookings()) ?? bookings
        app.syncReminders(for: bookings)
        openDeepLink()
    }

    private func openDeepLink() {
        guard case .booking(let id) = app.consumeDeepLink({ if case .booking = $0 { return true }; return false }) else { return }
        if let booking = bookings.first(where: { $0.id == id }) { path.append(booking) }
    }
}

struct BookingRow: View {
    let booking: Booking
    let perspective: UserRole

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(booking.startsAt.formatted(.dateTime.month(.abbreviated))).font(.caption2.bold()).foregroundStyle(Theme.accent)
                Text(booking.startsAt.formatted(.dateTime.day())).font(.title2.bold())
            }
            .frame(width: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(perspective == .artist ? booking.studioName : booking.artistName).font(.headline)
                Text("\(booking.sessionTypeName) · \(booking.startsAt.formatted(date: .omitted, time: .shortened))–\(booking.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
                StatusPill(text: booking.status.title, color: booking.status.color)
            }
            Spacer()
            Text(Money.format(perspective == .artist ? booking.price.total : booking.price.studioPayout, currency: booking.price.currency))
                .font(.subheadline.bold())
        }
        .padding(.vertical, 4)
    }
}

struct MonthCalendar: View {
    @Binding var selectedDay: Date
    var markedDays: Set<Date>
    var blockedDays: Set<Date> = []
    @State private var month = Date.now

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)

            let symbols = calendar.veryShortWeekdaySymbols
            let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { Text($0.element).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(days().enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
                        Button { selectedDay = day } label: {
                            VStack(spacing: 3) {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(calendar.isDateInToday(day) ? .bold : .regular))
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
                                    .background(isSelected ? Theme.accent : Color.clear, in: Circle())
                                HStack(spacing: 2) {
                                    Circle().fill(markedDays.contains(day) ? Theme.accent : .clear).frame(width: 5, height: 5)
                                    Circle().fill(blockedDays.contains(day) ? Color.red : Color.clear).frame(width: 5, height: 5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .card()
        .onAppear { month = selectedDay }
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }

    private func days() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (0..<count).map { interval.start.adding(days: $0) }
    }
}

// MARK: - Detail

struct BookingDetailView: View {
    @Environment(AppState.self) private var app
    let bookingId: UUID
    @State var initial: Booking

    @State private var transactions: [PaymentTransaction] = []
    @State private var studio: Studio?
    @State private var sheet: Sheet?
    @State private var conversation: Conversation?
    @State private var isWorking = false
    @State private var error: String?

    enum Sheet: Identifiable {
        case cancel, reschedule, review, dispute, decline, reportParty
        var id: Self { self }
    }

    private var booking: Booking { initial }
    private var isStudio: Bool { app.role == .studioOwner }

    var body: some View {
        List {
            summarySection
            requestSection
            actionsSection
            paymentSection
            receiptsSection
        }
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $conversation) { ChatView(conversation: $0) }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .cancel:
                CancelBookingSheet(booking: booking, policy: studio?.bookingPolicy.cancellationPolicy ?? .moderate, amountPaid: amountPaid, isStudio: isStudio) { updated in initial = updated }
            case .reschedule:
                if let studio { RescheduleSheet(booking: booking, studio: studio) { initial = $0 } }
            case .review:
                WriteReviewView(booking: booking) { initial.hasReview = true }
            case .dispute:
                TextPromptSheet(title: "Report a problem", placeholder: "What went wrong? Our team will review the booking and contact both sides.", action: "Send") { text in
                    try await app.backend.openDispute(bookingId: booking.id, reason: text)
                    initial.status = .disputed
                }
            case .reportParty:
                ReportSheet(target: isStudio ? .user : .studio, targetId: isStudio ? booking.artistId : booking.studioId)
            case .decline:
                TextPromptSheet(title: "Decline request", placeholder: "Optional message to the artist", action: "Decline", allowEmpty: true) { text in
                    initial = try await app.backend.respondToBooking(id: booking.id, accept: false, message: text.isEmpty ? nil : text)
                }
            }
        }
        .errorAlert($error)
    }


    // Sections are split out to keep type-checking fast.

    @ViewBuilder private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(text: booking.status.title, color: booking.status.color)
                Text(isStudio ? booking.artistName : booking.studioName).font(.title2.bold())
                Text("\(booking.sessionTypeName) · \(booking.hours) hours").foregroundStyle(.secondary)
            }
            InfoRow(symbol: "calendar", title: booking.startsAt.formatted(date: .complete, time: .omitted))
            InfoRow(symbol: "clock", title: "\(booking.startsAt.formatted(date: .omitted, time: .shortened)) – \(booking.endsAt.formatted(date: .omitted, time: .shortened))")
            InfoRow(symbol: "number", title: "Reference", value: booking.reference)
            if let studio, !isStudio, booking.status == .confirmed {
                InfoRow(symbol: "mappin.and.ellipse", title: studio.address.singleLine)
            }
            if !booking.notes.isEmpty {
                InfoRow(symbol: "text.bubble", title: booking.notes)
            }
            ForEach(booking.addOns) { addOn in
                InfoRow(symbol: "plus.circle", title: addOn.quantity > 1 ? "\(addOn.name) × \(addOn.quantity)" : addOn.name, value: Money.format(addOn.amount, currency: booking.price.currency))
            }
            if let reason = booking.cancellationReason {
                InfoRow(symbol: "xmark.circle", title: "Reason", value: reason)
            }
        }
    }

    @ViewBuilder private var requestSection: some View {
        if isStudio && booking.status == .pendingApproval {
            Section {
                Button { respond(accept: true) } label: { Label("Accept booking", systemImage: "checkmark.circle.fill") }
                Button(role: .destructive) { sheet = .decline } label: { Label("Decline", systemImage: "xmark.circle") }
            } footer: {
                Text(booking.isCash
                     ? "The artist will pay cash at the session."
                     : "The artist's card is authorised. Accepting charges it; declining releases the hold.")
            }
        }
    }

    @ViewBuilder private var actionsSection: some View {
        Section("Actions") {
            Button { openChat() } label: { Label(isStudio ? "Message artist" : "Message studio", systemImage: "bubble.left.and.bubble.right") }
            if let studio, !isStudio, booking.status == .confirmed {
                Button { LocationService.openDirections(to: studio) } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
            }
            if booking.canReschedule {
                Button { sheet = .reschedule } label: { Label("Change date or time", systemImage: "calendar.badge.clock") }
            }
            if !isStudio && booking.canReview {
                Button { sheet = .review } label: { Label("Write a review", systemImage: "star.bubble") }
            }
            if booking.canCancel {
                Button(role: .destructive) { sheet = .cancel } label: { Label("Cancel booking", systemImage: "xmark.octagon") }
            }
            if [.confirmed, .completed].contains(booking.status) {
                Button { sheet = .dispute } label: { Label("Report a problem", systemImage: "exclamationmark.bubble") }
            }
            Button { sheet = .reportParty } label: {
                Label(isStudio ? "Report artist" : "Report studio", systemImage: "flag")
            }
            NavigationLink { SupportCenterView(booking: booking) } label: {
                Label("Contact Sonora support", systemImage: "questionmark.circle")
            }
        }
    }

    @ViewBuilder private var paymentSection: some View {
        Section {
            if isStudio {
                PriceRow(title: "Session price", amount: booking.price.subtotal, currency: booking.price.currency)
                PriceRow(title: "Sonora platform fee (\(PlatformConfig.platformFeePercent)%)", amount: -booking.price.studioCommission, currency: booking.price.currency)
                PriceRow(title: booking.isCash ? "Yours to keep" : "Your payout", amount: booking.price.studioPayout, currency: booking.price.currency, emphasized: true)
            } else {
                PriceBreakdownView(price: booking.price)
            }
            InfoRow(symbol: booking.isCash ? "banknote" : "creditcard", title: "Status", value: booking.paymentStatus.title)
            if isStudio && booking.isCash && booking.paymentStatus == .payAtStudio && booking.startsAt <= .now && [.confirmed, .completed].contains(booking.status) {
                Button {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        do { initial = try await app.backend.markCashReceived(bookingId: booking.id) }
                        catch { self.error = error.userMessage }
                    }
                } label: {
                    Label("Mark cash as received", systemImage: "checkmark.circle")
                }
            }
            if booking.refundAmount > 0 {
                InfoRow(symbol: "arrow.uturn.backward", title: "Refunded", value: Money.format(booking.refundAmount, currency: booking.price.currency))
            }
        } header: {
            Text("Payment")
        } footer: {
            if booking.isCash {
                Text(isStudio
                     ? "Cash booking: collect \(Money.format(booking.price.total, currency: booking.price.currency)) at the session. Sonora's \(PlatformConfig.platformFeePercent)% fee is deducted from your next payout or invoiced."
                     : "Pay \(Money.format(booking.price.total, currency: booking.price.currency)) in cash at the studio.")
            }
        }
    }

    @ViewBuilder private var receiptsSection: some View {
        if !transactions.isEmpty {
            Section("Receipts") {
                ForEach(transactions) { transaction in
                    NavigationLink {
                        ReceiptView(booking: booking, transaction: transaction)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.kind == .refund ? "Refund" : transaction.kind == .balance ? "Balance payment" : "Payment")
                                Text(transaction.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((transaction.kind == .refund ? "−" : "") + Money.format(transaction.amount, currency: transaction.currency))
                                .foregroundStyle(transaction.kind == .refund ? Theme.positive : Color.primary)
                        }
                    }
                }
            }
        }
    }

    private var amountPaid: Int {
        transactions.filter { $0.status == .succeeded }.reduce(0) { $0 + ($1.kind == .refund ? -$1.amount : $1.amount) }
    }

    private func load() async {
        do {
            initial = try await app.backend.booking(id: bookingId)
            transactions = try await app.backend.transactions(bookingId: bookingId)
            if studio == nil { studio = try? await app.backend.studio(id: booking.studioId) }
        } catch { self.error = error.userMessage }
    }

    private func respond(accept: Bool) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                initial = try await app.backend.respondToBooking(id: booking.id, accept: accept, message: nil)
                transactions = try await app.backend.transactions(bookingId: bookingId)
            } catch { self.error = error.userMessage }
        }
    }

    private func openChat() {
        Task {
            do { conversation = try await app.backend.conversation(studioId: booking.studioId, bookingId: booking.id) }
            catch { self.error = error.userMessage }
        }
    }
}

struct CancelBookingSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let booking: Booking
    let policy: CancellationPolicy
    let amountPaid: Int
    let isStudio: Bool
    let onCancelled: (Booking) -> Void

    @State private var reason = ""
    @State private var isWorking = false
    @State private var error: String?

    private var refund: Int {
        if booking.paymentStatus == .authorized { return booking.price.dueNow }
        return RefundCalculator.refundAmount(price: booking.price, amountPaid: amountPaid, policy: policy, startsAt: booking.startsAt, cancelledBy: isStudio ? .studioOwner : .artist)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PriceRow(title: "Paid so far", amount: booking.paymentStatus == .authorized ? 0 : amountPaid, currency: booking.price.currency)
                    PriceRow(title: isStudio ? "Artist is refunded" : "You'll get back", amount: refund, currency: booking.price.currency, emphasized: true)
                } footer: {
                    Text(isStudio ? "When a studio cancels, the artist always gets a full refund. Frequent cancellations affect your listing." : "\(policy.title) policy: \(policy.summary)")
                }
                Section("Reason") {
                    TextField(isStudio ? "Let the artist know why" : "Optional", text: $reason, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Cancel booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Keep booking") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel booking", role: .destructive) {
                        isWorking = true
                        Task {
                            defer { isWorking = false }
                            do {
                                onCancelled(try await app.backend.cancelBooking(id: booking.id, reason: reason))
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(isWorking || (isStudio && reason.isEmpty))
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }
}

struct RescheduleSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let booking: Booking
    let studio: Studio
    let onChanged: (Booking) -> Void

    @State private var day = Date.now.startOfDay
    @State private var busy: [DateInterval] = []
    @State private var selected: TimeSlot?
    @State private var error: String?

    private var slots: [TimeSlot] {
        AvailabilityEngine().availableSlots(for: studio, on: day, hours: booking.hours, busy: busy.filter { $0 != booking.interval })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $day, in: Date.now.startOfDay..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("Same session type and length (\(booking.hours) h). To change the length, cancel and book again.")
                }
                Section("New start time") {
                    if slots.isEmpty { Text("No free slots this day.").foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))]) {
                        ForEach(slots) { slot in
                            Button(slot.start.formatted(date: .omitted, time: .shortened)) { selected = slot }
                                .buttonStyle(.bordered)
                                .tint(selected == slot ? Theme.accent : .gray)
                        }
                    }
                }
            }
            .navigationTitle("Change booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selected else { return }
                        Task {
                            do {
                                onChanged(try await app.backend.rescheduleBooking(id: booking.id, newStart: selected.start))
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(selected == nil)
                }
            }
            .task(id: day) {
                selected = nil
                busy = (try? await app.backend.busyIntervals(studioIds: [studio.id], from: day.adding(days: -1), to: day.adding(days: 2)))?[studio.id] ?? []
            }
            .onAppear { day = booking.startsAt.startOfDay }
            .errorAlert($error)
        }
    }
}

struct TextPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let action: String
    var allowEmpty = false
    let onSubmit: (String) async throws -> Void

    @State private var text = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(4...10)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action) {
                        isWorking = true
                        Task {
                            defer { isWorking = false }
                            do {
                                try await onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(isWorking || (!allowEmpty && text.trimmingCharacters(in: .whitespaces).count < 5))
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }
}

struct ReceiptView: View {
    let booking: Booking
    let transaction: PaymentTransaction

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    SonoraLogo(size: 20)
                    Text(transaction.kind == .refund ? "Refund receipt" : "Payment receipt").font(.headline)
                    Text(Money.format(transaction.amount, currency: transaction.currency)).font(.display(40))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                InfoRow(symbol: "number", title: "Receipt no.", value: transaction.receiptNumber)
                InfoRow(symbol: "calendar", title: "Date", value: transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                InfoRow(symbol: "creditcard", title: "Method", value: [transaction.method.title, transaction.cardBrand, transaction.cardLast4.map { "•••• \($0)" }].compactMap { $0 }.joined(separator: " "))
                InfoRow(symbol: "checkmark.circle", title: "Status", value: transaction.status.rawValue.capitalized)
            }
            Section("Booking") {
                InfoRow(symbol: "building.2", title: booking.studioName)
                InfoRow(symbol: "waveform", title: booking.sessionTypeName, value: "\(booking.hours) h")
                InfoRow(symbol: "calendar", title: booking.startsAt.formatted(date: .abbreviated, time: .shortened))
                InfoRow(symbol: "number", title: "Reference", value: booking.reference)
            }
            if transaction.kind == .charge {
                Section("Breakdown") { PriceBreakdownView(price: booking.price) }
            }
            Section {
                ShareLink(item: receiptText) { Label("Share receipt", systemImage: "square.and.arrow.up") }
            } footer: {
                Text("Sonora acts as payment agent for the studio. The service fee includes VAT where applicable.")
            }
        }
        .navigationTitle("Receipt")
    }

    private var receiptText: String {
        """
        Sonora receipt \(transaction.receiptNumber)
        \(transaction.kind == .refund ? "Refund" : "Payment"): \(Money.format(transaction.amount, currency: transaction.currency))
        Date: \(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
        Studio: \(booking.studioName)
        Session: \(booking.sessionTypeName), \(booking.startsAt.formatted(date: .abbreviated, time: .shortened)), \(booking.hours) h
        Booking ref: \(booking.reference)
        """
    }
}

struct BookingHistoryView: View {
    @Environment(AppState.self) private var app
    @State private var bookings: [Booking] = []

    var body: some View {
        List {
            if bookings.isEmpty {
                ContentUnavailableView("No bookings yet", systemImage: "clock")
            }
            ForEach(bookings) { booking in
                NavigationLink { BookingDetailView(bookingId: booking.id, initial: booking) } label: {
                    BookingRow(booking: booking, perspective: .artist)
                }
            }
        }
        .navigationTitle("Booking history")
        .task { bookings = (try? await app.backend.artistBookings()) ?? [] }
    }
}
