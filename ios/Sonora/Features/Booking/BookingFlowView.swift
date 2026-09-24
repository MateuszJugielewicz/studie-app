import SwiftUI
import EventKit

@MainActor
@Observable
final class BookingDraft {
    let studio: Studio
    var sessionTypeId: String
    var hours: Int
    var day: Date
    var selectedSlot: TimeSlot?
    var addOns: [String: Int] = [:]
    var notes = ""

    var busy: [DateInterval] = []
    var isLoadingSlots = false

    private let engine = AvailabilityEngine()

    init(studio: Studio) {
        self.studio = studio
        let first = studio.sessionTypes.first
        sessionTypeId = first?.id ?? ""
        hours = first?.minimumHours ?? 2
        day = Date.now.startOfDay
    }

    var sessionType: SessionType? { studio.sessionType(id: sessionTypeId) }

    var slots: [TimeSlot] { engine.availableSlots(for: studio, on: day, hours: hours, busy: busy) }

    var quote: PriceBreakdown? {
        sessionType.map { PricingEngine.quote(studio: studio, sessionType: $0, hours: hours, addOns: addOns) }
    }

    var request: BookingRequest? {
        guard let sessionType, let slot = selectedSlot else { return nil }
        return BookingRequest(studio: studio, sessionType: sessionType, startsAt: slot.start, hours: hours, addOns: addOns, notes: notes)
    }

    func loadBusy(_ backend: Backend) async {
        isLoadingSlots = true
        defer { isLoadingSlots = false }
        let start = day.startOfDay.adding(days: -1)
        busy = (try? await backend.busyIntervals(studioIds: [studio.id], from: start, to: start.adding(days: 3)))?[studio.id] ?? []
        if let selected = selectedSlot, !slots.contains(selected) { selectedSlot = nil }
    }
}

struct BookingFlowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BookingDraft
    @State private var goToCheckout = false

    init(studio: Studio) {
        _draft = State(initialValue: BookingDraft(studio: studio))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session type") {
                    Picker("Session type", selection: $draft.sessionTypeId) {
                        ForEach(draft.studio.sessionTypes) { type in
                            Text("\(type.name) · \(Money.format(type.hourlyRate, currency: draft.studio.currency))/h").tag(type.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Duration") {
                    Stepper(value: $draft.hours, in: (draft.sessionType?.minimumHours ?? 1)...PlatformConfig.maxSessionHours) {
                        Text("\(draft.hours) hours").bold()
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $draft.day, in: Date.now.startOfDay...Date.now.adding(days: draft.studio.bookingPolicy.maxAdvanceDays), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section {
                    if draft.isLoadingSlots {
                        ProgressView()
                    } else if draft.slots.isEmpty {
                        Text(AvailabilityEngine().openingWindow(for: draft.studio, on: draft.day) == nil ? "The studio is closed this day." : "No free \(draft.hours)-hour slots this day. Try fewer hours or another date.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 8) {
                            ForEach(draft.slots) { slot in
                                Button {
                                    draft.selectedSlot = slot
                                } label: {
                                    Text(slot.start.formatted(date: .omitted, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(draft.selectedSlot == slot ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(draft.selectedSlot == slot ? Theme.onAccent : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Start time")
                } footer: {
                    if let slot = draft.selectedSlot {
                        Text("\(slot.start.formatted(date: .complete, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                    }
                }

                if !draft.studio.addOns.isEmpty {
                    Section("Add-ons") {
                        ForEach(draft.studio.addOns) { addOn in
                            AddOnRow(addOn: addOn, currency: draft.studio.currency, quantity: Binding(
                                get: { draft.addOns[addOn.id] ?? 0 },
                                set: { draft.addOns[addOn.id] = $0 }
                            ))
                        }
                    }
                }

                Section("Notes for the studio") {
                    TextField("What are you working on? Anything they should prepare?", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let quote = draft.quote {
                    Section("Price") {
                        PriceBreakdownView(price: quote)
                    }
                }
            }
            .navigationTitle(draft.studio.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    goToCheckout = true
                } label: {
                    Text(draft.selectedSlot == nil ? "Pick a time" : "Continue · \(Money.format(draft.quote?.total ?? 0, currency: draft.studio.currency))")
                }
                .buttonStyle(.primary)
                .disabled(draft.request == nil)
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationDestination(isPresented: $goToCheckout) {
                if let request = draft.request {
                    CheckoutView(request: request, onFinish: { dismiss() })
                }
            }
            .task(id: draft.day) { await draft.loadBusy(app.backend) }
            .onChange(of: draft.sessionTypeId) {
                if let minimum = draft.sessionType?.minimumHours, draft.hours < minimum { draft.hours = minimum }
            }
            .onChange(of: draft.hours) {
                if let selected = draft.selectedSlot, !draft.slots.contains(where: { $0.start == selected.start }) {
                    draft.selectedSlot = nil
                } else if let selected = draft.selectedSlot {
                    draft.selectedSlot = draft.slots.first { $0.start == selected.start }
                }
            }
        }
    }
}

struct AddOnRow: View {
    let addOn: ServiceAddOn
    let currency: String
    @Binding var quantity: Int

    var body: some View {
        VStack(alignment: .leading) {
            if addOn.unit == .perTrack {
                Stepper(value: $quantity, in: 0...20) {
                    label
                    if quantity > 0 { Text("\(quantity) track\(quantity == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.accent) }
                }
            } else {
                Toggle(isOn: Binding(get: { quantity > 0 }, set: { quantity = $0 ? 1 : 0 })) { label }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading) {
            Text(addOn.name)
            Text("\(Money.format(addOn.price, currency: currency)) \(addOn.unit.suffix)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PriceBreakdownView: View {
    let price: PriceBreakdown

    var body: some View {
        VStack(spacing: 8) {
            PriceRow(title: "\(Money.format(price.hourlyRate, currency: price.currency)) × \(price.hours) h", amount: price.sessionAmount, currency: price.currency)
            if price.addOnsAmount > 0 {
                PriceRow(title: "Add-ons", amount: price.addOnsAmount, currency: price.currency)
            }
            if price.serviceFee > 0 {
                PriceRow(title: "Service fee", amount: price.serviceFee, currency: price.currency)
            }
            Divider()
            PriceRow(title: "Total", amount: price.total, currency: price.currency, emphasized: true)
            if price.depositAmount > 0 {
                PriceRow(title: "Due now (deposit + fee)", amount: price.dueNow, currency: price.currency)
                PriceRow(title: "Charged after the session", amount: price.dueLater, currency: price.currency)
            }
        }
    }
}

// MARK: - Checkout

struct CheckoutView: View {
    @Environment(AppState.self) private var app
    let request: BookingRequest
    let onFinish: () -> Void

    @State private var method: PaymentMethod = .applePay
    @State private var payWithCash = false
    @State private var agreed = false
    @State private var isPaying = false
    @State private var confirmed: Booking?
    @State private var error: String?

    /// Card/Apple Pay needs Stripe keys; cash needs a studio that accepts it.
    private var cardAvailable: Bool { AppConfig.stripePublishableKey != nil }
    private var cashAvailable: Bool { PricingEngine.acceptsCash(request.studio) }

    private var price: PriceBreakdown {
        PricingEngine.quote(studio: request.studio, sessionType: request.sessionType, hours: request.hours, addOns: request.addOns)
    }

    var body: some View {
        Form {
            Section("Your session") {
                InfoRow(symbol: "building.2", title: request.studio.name)
                InfoRow(symbol: "waveform", title: request.sessionType.name, value: "\(request.hours) h")
                InfoRow(symbol: "calendar", title: request.startsAt.formatted(date: .abbreviated, time: .omitted), value: "\(request.startsAt.formatted(date: .omitted, time: .shortened)) – \(request.startsAt.adding(hours: request.hours).formatted(date: .omitted, time: .shortened))")
            }

            Section("Payment") {
                PriceBreakdownView(price: price)
            }

            if cashAvailable && cardAvailable {
                Section {
                    Picker("Payment", selection: $payWithCash) {
                        Label("Pay now in the app", systemImage: "creditcard").tag(false)
                        Label("Pay cash at the studio", systemImage: "banknote").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("How do you want to pay?")
                } footer: {
                    if payWithCash {
                        Text("Bring \(Money.format(price.total, currency: price.currency)) in cash to your session. Paying in the app gives you automatic refunds under the cancellation policy.")
                    }
                }
            }

            if payWithCash {
                Section {
                    Label("Pay \(Money.format(price.total, currency: price.currency)) in cash at the session.", systemImage: "banknote")
                        .font(.footnote)
                }
            } else if cardAvailable {
                Section {
                    Label("Card or Apple Pay – securely processed by Stripe.", systemImage: "lock.shield")
                        .font(.footnote)
                }
            } else {
                Section {
                    Label("In-app payment isn't available yet, and this studio doesn't accept cash. Message the studio to arrange your session.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }

            Section {
                Toggle(isOn: $agreed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I agree to the studio's rules and the \(request.studio.bookingPolicy.cancellationPolicy.title.lowercased()) cancellation policy.")
                        Text(request.studio.bookingPolicy.cancellationPolicy.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            } footer: {
                if !request.studio.bookingPolicy.instantBook && !payWithCash {
                    Text("This studio confirms requests manually. Your card is authorised now and only charged if they accept.")
                }
            }
        }
        .navigationTitle("Checkout")
        .safeAreaInset(edge: .bottom) {
            Button { pay() } label: {
                if isPaying {
                    ProgressView().tint(.white)
                } else {
                    Text(payWithCash
                         ? (request.studio.bookingPolicy.instantBook ? "Book · pay cash at the studio" : "Request to book · pay cash")
                         : (request.studio.bookingPolicy.instantBook ? "Pay \(Money.format(price.dueNow, currency: price.currency))" : "Request to book · \(Money.format(price.dueNow, currency: price.currency))"))
                }
            }
            .buttonStyle(.primary)
            .disabled(!agreed || isPaying || (!payWithCash && !cardAvailable))
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationDestination(item: $confirmed) { booking in
            BookingConfirmationView(booking: booking, onDone: onFinish)
        }
        .onAppear {
            if !cardAvailable && cashAvailable { payWithCash = true }
        }
        .errorAlert($error)
    }

    private func pay() {
        isPaying = true
        Task {
            defer { isPaying = false }
            do {
                let booking = try await app.backend.createBooking(request)
                if payWithCash {
                    confirmed = try await app.backend.confirmCashBooking(bookingId: booking.id)
                    await app.refreshBadges()
                    return
                }
                let intent = try await app.backend.preparePayment(bookingId: booking.id, method: method)
                let outcome = try await StripePaymentProcessor.pay(intent)
                if case .cancelled = outcome { return }
                confirmed = try await app.backend.confirmPayment(bookingId: booking.id, method: method)
                await app.refreshBadges()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

struct BookingConfirmationView: View {
    @Environment(AppState.self) private var app
    let booking: Booking
    let onDone: () -> Void
    @State private var addedToCalendar = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: booking.status == .confirmed ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(booking.status == .confirmed ? Theme.positive : Theme.warning)
                    .padding(.top, 32)
                Text(booking.status == .confirmed ? "You're booked!" : "Request sent")
                    .font(.largeTitle.bold())
                Text(booking.status == .confirmed
                     ? (booking.isCash ? "Pay \(Money.format(booking.price.total, currency: booking.price.currency)) in cash at the studio. We'll remind you before your session." : "We've sent a confirmation and receipt. We'll remind you before your session.")
                     : "\(booking.studioName) will respond within 24 hours." + (booking.isCash ? "" : " You're only charged if they accept."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    InfoRow(symbol: "number", title: "Reference", value: booking.reference)
                    InfoRow(symbol: "building.2", title: booking.studioName)
                    InfoRow(symbol: "calendar", title: booking.startsAt.formatted(date: .complete, time: .omitted))
                    InfoRow(symbol: "clock", title: "\(booking.startsAt.formatted(date: .omitted, time: .shortened)) – \(booking.endsAt.formatted(date: .omitted, time: .shortened))")
                    InfoRow(symbol: booking.isCash ? "banknote" : "creditcard", title: booking.paymentStatus.title, value: Money.format(booking.isCash ? booking.price.total : booking.price.dueNow, currency: booking.price.currency))
                }
                .card()

                Button {
                    Task {
                        do {
                            try await CalendarExporter.add(booking)
                            addedToCalendar = true
                        } catch { self.error = error.userMessage }
                    }
                } label: {
                    Label(addedToCalendar ? "Added to calendar" : "Add to calendar", systemImage: addedToCalendar ? "checkmark" : "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(addedToCalendar)

                Button("Done") {
                    app.selectedTab = .bookings
                    onDone()
                }
                .buttonStyle(.primary)
            }
            .padding()
        }
        .navigationBarBackButtonHidden()
        .onAppear { app.syncReminders(for: [booking]) }
        .errorAlert($error)
    }
}

enum CalendarExporter {
    static func add(_ booking: Booking) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else {
            throw BackendError.validation("Allow calendar access in Settings to add sessions.")
        }
        let event = EKEvent(eventStore: store)
        event.title = "\(booking.sessionTypeName) · \(booking.studioName)"
        event.startDate = booking.startsAt
        event.endDate = booking.endsAt
        event.notes = "Sonora booking \(booking.reference)"
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        try store.save(event, span: .thisEvent)
    }
}
