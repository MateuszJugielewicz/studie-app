import SwiftUI
import Charts

struct StudioOwnerRootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let studio = app.ownedStudio {
            switch studio.status {
            case .approved, .suspended:
                StudioTabView()
            case .draft, .pendingReview, .changesRequested, .rejected:
                NavigationStack { ApplicationStatusView(studio: studio) }
            }
        } else if let account = app.account {
            NavigationStack {
                StudioEditorView(studio: .newDraft(ownerId: account.id), isApplication: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Sign out") { Task { await app.signOut() } }
                        }
                    }
            }
        }
    }
}

struct ApplicationStatusView: View {
    @Environment(AppState.self) private var app
    let studio: Studio
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    StatusPill(text: studio.status.title, color: studio.status.color)
                    Text(studio.name.isEmpty ? "Your studio" : studio.name).font(.title.bold())
                    Text(statusText).foregroundStyle(.secondary)
                    if let note = studio.adminNote, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Message from the Sonora team").font(.caption.bold())
                            Text(note)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section {
                ApplicationStep(title: "Create your listing", done: true)
                ApplicationStep(title: "Submit for review", done: studio.status != .draft)
                ApplicationStep(title: "Sonora reviews your studio", done: studio.status == .approved, active: studio.status == .pendingReview)
                ApplicationStep(title: "Go live – artists can find, book and pay", done: studio.status == .approved)
            }

            Section {
                NavigationLink {
                    StudioEditorView(studio: studio, isApplication: true)
                } label: {
                    Label("Edit listing", systemImage: "pencil")
                }
                if studio.status != .pendingReview {
                    Button {
                        submit()
                    } label: {
                        Label(isSubmitting ? "Submitting…" : "Submit for review", systemImage: "paperplane.fill")
                    }
                    .disabled(isSubmitting)
                }
            }

            if app.isDemo, studio.status == .pendingReview, let mock = app.backend as? MockBackend {
                Section {
                    Button("Simulate approval") { decide(mock, approve: true) }
                    Button("Simulate “changes requested”") { decide(mock, approve: false) }
                } header: {
                    Text("Demo only")
                } footer: {
                    Text("In production this happens in the admin dashboard.")
                }
            }

            Section {
                Button("Sign out") { Task { await app.signOut() } }
            }
        }
        .navigationTitle("Application")
        .refreshable { app.ownedStudio = try? await app.backend.ownedStudio() }
        .errorAlert($error)
    }

    private var statusText: String {
        switch studio.status {
        case .draft: "Finish your listing and submit it. Our team checks every studio before it becomes visible."
        case .pendingReview: "Thanks! We're reviewing your studio and will notify you, usually within 1–2 business days."
        case .changesRequested: "We need a few changes before we can approve your studio. Update your listing and resubmit."
        case .rejected: "Unfortunately your studio wasn't approved. You can update your listing and apply again."
        default: ""
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do { app.ownedStudio = try await app.backend.submitStudioForReview(id: studio.id) }
            catch { self.error = error.userMessage }
        }
    }

    private func decide(_ mock: MockBackend, approve: Bool) {
        mock.simulateAdminDecision(studioId: studio.id, approve: approve, note: approve ? nil : "Please add photos of your vocal booth and list your microphones.")
        Task {
            app.ownedStudio = try? await app.backend.ownedStudio()
            await app.refreshBadges()
        }
    }
}

struct ApplicationStep: View {
    let title: String
    let done: Bool
    var active = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "clock.fill" : "circle")
                .foregroundStyle(done ? .green : active ? .orange : .secondary)
        }
    }
}

struct StudioTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            StudioDashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(AppTab.dashboard)
            StudioCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            ConversationsView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                .badge(app.unreadMessages)
                .tag(AppTab.messages)
            NotificationsView()
                .tabItem { Label("Inbox", systemImage: "bell") }
                .badge(app.unreadNotifications)
                .tag(AppTab.notifications)
            StudioSettingsView()
                .tabItem { Label("Studio", systemImage: "building.2") }
                .tag(AppTab.profile)
        }
    }
}

@MainActor
@Observable
final class StudioDashboardModel {
    var bookings: [Booking] = []
    var payouts: [Payout] = []
    var reviews: [Review] = []

    func load(_ backend: Backend, studioId: UUID) async {
        async let bookings = backend.studioBookings(studioId: studioId)
        async let payouts = backend.payouts(studioId: studioId)
        async let reviews = backend.reviews(studioId: studioId)
        self.bookings = (try? await bookings) ?? self.bookings
        self.payouts = (try? await payouts) ?? self.payouts
        self.reviews = (try? await reviews) ?? self.reviews
    }

    var requests: [Booking] { bookings.filter { $0.status == .pendingApproval }.sorted { $0.startsAt < $1.startsAt } }
    var upcoming: [Booking] { bookings.filter { $0.status == .confirmed && $0.endsAt > .now }.sorted { $0.startsAt < $1.startsAt } }
    var past: [Booking] { bookings.filter { !$0.isUpcoming && $0.status != .pendingApproval } }
}

struct StudioDashboardView: View {
    @Environment(AppState.self) private var app
    @State private var model = StudioDashboardModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            if let studio = app.ownedStudio {
                let summary = EarningsCalculator.summary(bookings: model.bookings, payouts: model.payouts, currency: studio.currency)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if studio.status == .suspended {
                            Label("Your studio is suspended and hidden from artists. Contact support.", systemImage: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red).card()
                        }
                        LiveToggleCard(studio: studio)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatCard(title: "This month", value: Money.format(summary.netThisMonth, currency: studio.currency), symbol: "chart.line.uptrend.xyaxis")
                            StatCard(title: "Upcoming payouts", value: Money.format(summary.pendingPayout, currency: studio.currency), symbol: "banknote")
                            StatCard(title: "Upcoming sessions", value: "\(summary.upcomingSessions)", symbol: "calendar")
                            StatCard(title: "Rating", value: studio.reviewCount == 0 ? "–" : String(format: "%.1f ★", studio.ratingAverage), symbol: "star")
                        }

                        if !model.requests.isEmpty {
                            SectionHeader(title: "Requests (\(model.requests.count))")
                            ForEach(model.requests) { booking in
                                NavigationLink(value: booking) { BookingRow(booking: booking, perspective: .studioOwner).card() }
                                    .buttonStyle(.plain)
                            }
                        }

                        SectionHeader(title: "Upcoming bookings")
                        if model.upcoming.isEmpty {
                            Text("No upcoming bookings yet.").foregroundStyle(.secondary)
                        }
                        ForEach(model.upcoming.prefix(5)) { booking in
                            NavigationLink(value: booking) { BookingRow(booking: booking, perspective: .studioOwner).card() }
                                .buttonStyle(.plain)
                        }

                        SectionHeader(title: "Manage")
                        VStack(spacing: 0) {
                            ManageLink(title: "Earnings & payouts", symbol: "chart.bar.fill") {
                                EarningsView(studio: studio, bookings: model.bookings, payouts: model.payouts)
                            }
                            ManageLink(title: "Past bookings", symbol: "clock.arrow.circlepath") {
                                StudioBookingListView(title: "Past bookings", bookings: model.past)
                            }
                            ManageLink(title: "Prices & services", symbol: "eurosign.circle") {
                                StudioSectionEditor(title: "Prices & services") { StudioPricingEditor(studio: $0) }
                            }
                            ManageLink(title: "Opening hours", symbol: "clock") {
                                StudioSectionEditor(title: "Opening hours") { OpeningHoursEditor(hours: $0.openingHours) }
                            }
                            ManageLink(title: "Reviews (\(model.reviews.count))", symbol: "star.bubble") {
                                ReviewsListView(studio: studio, reviews: model.reviews, canReply: true)
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
                    }
                    .padding()
                }
                .background(Theme.background)
                .navigationTitle(studio.name)
                .navigationDestination(for: Booking.self) { BookingDetailView(bookingId: $0.id, initial: $0) }
                .refreshable { await reload(studio) }
                .task { await reload(studio) }
                .onChange(of: path.count) { if path.isEmpty { Task { await reload(studio) } } }
            }
        }
    }

    private func reload(_ studio: Studio) async {
        await model.load(app.backend, studioId: studio.id)
        app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio
    }
}

/// Wraps a section editor with a save button bound to the owned studio.
struct StudioSectionEditor<Content: View>: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: (Binding<Studio>) -> Content
    @State private var draft: Studio?
    @State private var error: String?

    var body: some View {
        Group {
            if let binding = Binding($draft) {
                content(binding)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let draft else { return }
                    Task {
                        do {
                            app.ownedStudio = try await app.backend.saveStudio(draft)
                            dismiss()
                        } catch { self.error = error.userMessage }
                    }
                }
            }
        }
        .onAppear { if draft == nil { draft = app.ownedStudio } }
        .errorAlert($error)
    }
}

struct ManageLink<Destination: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
}

struct LiveToggleCard: View {
    @Environment(AppState.self) private var app
    let studio: Studio
    @State private var error: String?

    var body: some View {
        Toggle(isOn: Binding(get: { studio.isActive }, set: { newValue in
            Task {
                do { app.ownedStudio = try await app.backend.setStudioActive(id: studio.id, isActive: newValue) }
                catch { self.error = error.userMessage }
            }
        })) {
            VStack(alignment: .leading) {
                Text(studio.isActive ? "Live on Sonora" : "Paused").font(.headline)
                Text(studio.isActive ? "Artists can find and book you." : "Hidden from search. Existing bookings are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(studio.status != .approved)
        .card()
        .errorAlert($error)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct StudioBookingListView: View {
    let title: String
    let bookings: [Booking]

    var body: some View {
        List {
            if bookings.isEmpty { ContentUnavailableView("Nothing here yet", systemImage: "calendar") }
            ForEach(bookings) { booking in
                NavigationLink { BookingDetailView(bookingId: booking.id, initial: booking) } label: {
                    BookingRow(booking: booking, perspective: .studioOwner)
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Calendar

struct StudioCalendarView: View {
    @Environment(AppState.self) private var app
    @State private var bookings: [Booking] = []
    @State private var blocked: [BlockedSlot] = []
    @State private var selectedDay = Date.now.startOfDay
    @State private var showBlock = false
    @State private var path = NavigationPath()
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                MonthCalendar(
                    selectedDay: $selectedDay,
                    markedDays: Set(bookings.filter { $0.status.isActive || $0.status == .completed }.map { $0.startsAt.startOfDay }),
                    blockedDays: Set(blocked.map { $0.startsAt.startOfDay })
                )
                .listRowBackground(Color.clear)

                if let studio = app.ownedStudio {
                    let window = AvailabilityEngine().openingWindow(for: studio, on: selectedDay)
                    Section(selectedDay.formatted(date: .complete, time: .omitted)) {
                        if let window {
                            Label("Open \(window.start.formatted(date: .omitted, time: .shortened)) – \(window.end.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Closed", systemImage: "moon.zzz").foregroundStyle(.secondary)
                        }
                        ForEach(bookings.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: selectedDay) && $0.status != .expired }) { booking in
                            NavigationLink(value: booking) { BookingRow(booking: booking, perspective: .studioOwner) }
                        }
                        ForEach(blocked.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: selectedDay) }) { slot in
                            HStack {
                                Image(systemName: "nosign").foregroundStyle(.red)
                                VStack(alignment: .leading) {
                                    Text("Blocked · \(slot.reason.isEmpty ? "Unavailable" : slot.reason)")
                                    Text("\(slot.startsAt.formatted(date: .omitted, time: .shortened)) – \(slot.endsAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Unblock", role: .destructive) { unblock(slot) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationDestination(for: Booking.self) { BookingDetailView(bookingId: $0.id, initial: $0) }
            .toolbar {
                Button { showBlock = true } label: { Label("Block time", systemImage: "nosign") }
            }
            .sheet(isPresented: $showBlock) {
                if let studio = app.ownedStudio {
                    BlockTimeSheet(studioId: studio.id, day: selectedDay) { blocked.append($0) }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: app.pendingDeepLink) { openDeepLink() }
            .errorAlert($error)
        }
    }

    private func load() async {
        guard let studio = app.ownedStudio else { return }
        bookings = (try? await app.backend.studioBookings(studioId: studio.id)) ?? bookings
        blocked = (try? await app.backend.blockedSlots(studioId: studio.id)) ?? blocked
        openDeepLink()
    }

    private func openDeepLink() {
        guard case .booking(let id) = app.consumeDeepLink({ if case .booking = $0 { return true }; return false }) else { return }
        if let booking = bookings.first(where: { $0.id == id }) {
            selectedDay = booking.startsAt.startOfDay
            path.append(booking)
        }
    }

    private func unblock(_ slot: BlockedSlot) {
        Task {
            do {
                try await app.backend.removeBlockedSlot(id: slot.id)
                blocked.removeAll { $0.id == slot.id }
            } catch { self.error = error.userMessage }
        }
    }
}

struct BlockTimeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let studioId: UUID
    let day: Date
    let onAdded: (BlockedSlot) -> Void

    @State private var start = Date.now
    @State private var end = Date.now
    @State private var allDay = false
    @State private var reason = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Toggle("All day", isOn: $allDay)
                DatePicker("From", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                if !allDay {
                    DatePicker("To", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Reason (private)", text: $reason)
            }
            .navigationTitle("Block time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Block") {
                        let from = allDay ? start.startOfDay : start
                        let to = allDay ? start.startOfDay.adding(days: 1) : end
                        Task {
                            do {
                                onAdded(try await app.backend.addBlockedSlot(BlockedSlot(id: UUID(), studioId: studioId, startsAt: from, endsAt: to, reason: reason)))
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                }
            }
            .onAppear {
                start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
                end = start.adding(hours: 2)
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Earnings

struct EarningsView: View {
    @Environment(AppState.self) private var app
    let studio: Studio
    let bookings: [Booking]
    let payouts: [Payout]

    var body: some View {
        let summary = EarningsCalculator.summary(bookings: bookings, payouts: payouts, currency: studio.currency)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Earned this month").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(summary.netThisMonth, currency: studio.currency)).font(.largeTitle.bold())
                    Text("\(Money.format(summary.grossThisMonth, currency: studio.currency)) booked · \(PlatformConfig.studioCommissionPercent)% commission")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Chart(summary.monthly) { item in
                    BarMark(x: .value("Month", item.month, unit: .month), y: .value("Earnings", Double(item.amount) / 100))
                        .foregroundStyle(Theme.gradient)
                        .cornerRadius(4)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 180)
            }

            Section("Totals") {
                InfoRow(symbol: "sum", title: "All-time earnings", value: Money.format(summary.netAllTime, currency: studio.currency))
                InfoRow(symbol: "checkmark.circle", title: "Completed sessions", value: "\(summary.completedSessions)")
                InfoRow(symbol: "clock", title: "Hours booked", value: "\(summary.hoursBooked)")
                InfoRow(symbol: "hourglass", title: "Upcoming payouts", value: Money.format(summary.pendingPayout, currency: studio.currency))
            }

            Section("Payouts") {
                if payouts.isEmpty { Text("Payouts appear here after your first completed session.").foregroundStyle(.secondary) }
                ForEach(payouts) { payout in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Money.format(payout.amount, currency: payout.currency)).font(.headline)
                            Text(payout.status == .paid ? "Paid \((payout.paidAt ?? payout.scheduledFor).formatted(date: .abbreviated, time: .omitted))" : "Expected \(payout.scheduledFor.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(text: payout.status.title, color: payout.status == .paid ? .green : payout.status == .failed ? .red : .orange)
                    }
                }
            }

            Section {
                NavigationLink { PayoutAccountEditor(studioId: studio.id) } label: { Label("Payout details", systemImage: "building.columns") }
            }
        }
        .navigationTitle("Earnings")
    }
}

// MARK: - Studio settings tab

struct StudioSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                if let studio = app.ownedStudio {
                    Section {
                        HStack(spacing: 12) {
                            RemoteImage(url: studio.photoUrls.first).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(studio.name).font(.headline)
                                    if studio.isVerified { VerifiedBadge() }
                                }
                                Text(studio.address.publicArea).font(.subheadline).foregroundStyle(.secondary)
                                StatusPill(text: studio.isActive ? "Live" : studio.status.title, color: studio.isActive ? .green : studio.status.color)
                            }
                        }
                    }
                    Section {
                        NavigationLink { StudioDetailView(studioId: studio.id, initial: studio) } label: { Label("Preview public profile", systemImage: "eye") }
                        NavigationLink { StudioEditorView(studio: studio, isApplication: false) } label: { Label("Edit studio profile", systemImage: "pencil") }
                        NavigationLink { PayoutAccountEditor(studioId: studio.id) } label: { Label("Payout details", systemImage: "building.columns") }
                    }
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label("Account & notifications", systemImage: "gearshape") }
                    Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) { Label("Studio support", systemImage: "questionmark.circle") }
                }
            }
            .navigationTitle("Studio")
        }
    }
}
