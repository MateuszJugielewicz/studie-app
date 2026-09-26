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
                    // An application may already exist (e.g. saved from another device); edit that instead of a new draft.
                    .task { app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio }
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
        EasySeshScreen("Application", eyebrow: studio.name.isEmpty ? L10n.tr("Your studio") : studio.name,
                     refresh: { app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio }) {
            statusCard
            if let note = studio.adminNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: "text.bubble.fill", size: 36, colors: [Theme.warning, Theme.accent])
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message from the EasySesh team").font(.subheadline.weight(.bold))
                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            steps
            VStack(spacing: 10) {
                if studio.status != .pendingReview {
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill") }
                            Text(isSubmitting ? LocalizedStringKey("Submitting…") : LocalizedStringKey("Submit for review"))
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isSubmitting)
                }
                NavigationLink {
                    StudioEditorView(studio: studio, isApplication: true)
                } label: {
                    Label("Edit listing", systemImage: "pencil")
                }
                .buttonStyle(.secondary)
            }
            SignOutButton()
        }
        .errorAlert($error)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PulseDot(color: studio.status.color, isActive: studio.status == .pendingReview)
                Text(localized: studio.status.title)
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(studio.status.color)
            }
            Text(localized: statusText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 18, cornerRadius: 24)
        .overlay(alignment: .leading) {
            Capsule().fill(Theme.neon).frame(width: 4).padding(.vertical, 18)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ApplicationStep(title: "Create your listing", done: true, isLast: false)
            ApplicationStep(title: "Submit for review", done: studio.status != .draft, isLast: false)
            ApplicationStep(title: "EasySesh reviews your studio", done: studio.status == .approved, active: studio.status == .pendingReview, isLast: false)
            ApplicationStep(title: "Go live – artists can find, book and pay", done: studio.status == .approved, isLast: true)
        }
        .glassCard(padding: 16, cornerRadius: 24)
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
}

/// One row of the application timeline, with a gradient connector to the next step.
struct ApplicationStep: View {
    let title: LocalizedStringKey
    let done: Bool
    var active = false
    var isLast = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(done ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.08)))
                        .frame(width: 30, height: 30)
                    Image(systemName: done ? "checkmark" : active ? "hourglass" : "circle.dotted")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(done ? Color.white : active ? Theme.warning : Color.secondary)
                        .symbolEffect(.pulse, isActive: active)
                }
                .neonGlow(Theme.magenta, radius: 8, active: done)
                if !isLast {
                    Rectangle()
                        .fill(done ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.1)))
                        .frame(width: 2, height: 26)
                }
            }
            Text(title)
                .font(.subheadline.weight(done || active ? .bold : .regular))
                .foregroundStyle(done || active ? Color.primary : Color.secondary)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
    }
}

struct StudioTabView: View {
    @Environment(AppState.self) private var app
    @Environment(AppPreferences.self) private var preferences

    /// The walkthrough plays once, the first time an approved studio opens the app.
    private var tour: TabTour? {
        guard let studio = app.ownedStudio, studio.status == .approved, !preferences.hasCompletedTour(studioId: studio.id) else { return nil }
        return .studioApproved { preferences.completeTour(studioId: studio.id) }
    }

    var body: some View {
        @Bindable var app = app
        EasySeshTabContainer(selection: $app.selectedTab, tour: tour, tabs: [
            TabSpec(tab: .dashboard, title: "Dashboard", symbol: "square.grid.2x2"),
            TabSpec(tab: .calendar, title: "Calendar", symbol: "calendar"),
            TabSpec(tab: .messages, title: "Messages", symbol: "bubble.left.and.bubble.right", badge: app.unreadMessages),
            TabSpec(tab: .notifications, title: "Inbox", symbol: "bell", badge: app.unreadNotifications),
            TabSpec(tab: .profile, title: "Studio", symbol: "building.2"),
        ]) { tab in
            switch tab {
            case .calendar: StudioCalendarView()
            case .messages: ConversationsView()
            case .notifications: NotificationsView()
            case .profile: StudioSettingsView()
            default: StudioDashboardView()
            }
        }
    }
}

@MainActor
@Observable
final class StudioDashboardModel {
    var bookings: [Booking] = []
    var payouts: [Payout] = []
    var reviews: [Review] = []
    var fees: [FeeLedgerEntry] = []

    func load(_ backend: Backend, studioId: UUID) async {
        bookings = (try? await backend.studioBookings(studioId: studioId)) ?? bookings
        payouts = (try? await backend.payouts(studioId: studioId)) ?? payouts
        reviews = (try? await backend.reviews(studioId: studioId)) ?? reviews
        fees = (try? await backend.feeLedger(studioId: studioId)) ?? fees
    }

    /// Platform fees owed for cash bookings, per currency.
    var feesOwed: Int { fees.reduce(0) { $0 + $1.amount } }

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
                EasySeshScreen(studio.name, eyebrow: Date.now.greeting, refresh: { await reload(studio) }) {
                    NavigationLink { StudioDetailView(studioId: studio.id, initial: studio) } label: { GlassIcon(symbol: "eye") }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityLabel("Preview public profile")
                } content: {
                    StudioDashboardContent(studio: studio, model: model)
                }
                .navigationDestination(for: Booking.self) { BookingDetailView(bookingId: $0.id, initial: $0) }
                .task { await reload(studio) }
                .onChange(of: path.count) {
                    if path.isEmpty { Task { await reload(studio) } }
                }
            }
        }
    }

    private func reload(_ studio: Studio) async {
        await model.load(app.backend, studioId: studio.id)
        app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio
    }
}

private struct StudioDashboardContent: View {
    let studio: Studio
    let model: StudioDashboardModel

    private var summary: EarningsSummary {
        EarningsCalculator.summary(bookings: model.bookings, payouts: model.payouts, currency: studio.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if studio.status == .suspended {
                HStack(spacing: 12) {
                    IconTile(symbol: "exclamationmark.octagon.fill", colors: [Color.red, Theme.magenta])
                    Text("Your studio is suspended and hidden from artists. Contact support.").font(.subheadline)
                }
                .glassCard()
            }
            LiveToggleCard(studio: studio)
            EarningsHeroCard(studio: studio, summary: summary)
            stats
            if model.feesOwed > 0 {
                HStack(spacing: 12) {
                    IconTile(symbol: "banknote", colors: TilePalette.violet)
                    Text("You owe \(Money.format(model.feesOwed, currency: studio.currency)) in platform fees for cash bookings. It's deducted from your next payout.")
                        .font(.footnote)
                }
                .glassCard()
            }
            requests
            upcoming
            manage
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatCard(title: "Upcoming", value: "\(summary.upcomingSessions)", symbol: "calendar", colors: TilePalette.ocean)
            StatCard(title: "Requests", value: "\(model.requests.count)", symbol: "tray.and.arrow.down", colors: TilePalette.signal)
            StatCard(title: "Rating", value: studio.reviewCount == 0 ? "–" : String(format: "%.1f", studio.ratingAverage), symbol: "star.fill", colors: TilePalette.violet)
        }
    }

    @ViewBuilder private var requests: some View {
        if !model.requests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GlowSectionHeader(title: "Requests", count: model.requests.count)
                ForEach(model.requests) { booking in
                    NavigationLink(value: booking) {
                        BookingRow(booking: booking, perspective: .studioOwner)
                            .glassCard(padding: 12)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.neon).frame(width: 3).padding(.vertical, 14)
                            }
                    }
                    .buttonStyle(PressableCardStyle())
                    .scrollReveal()
                }
            }
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Upcoming")
            if model.upcoming.isEmpty {
                GlassEmptyState(title: "No upcoming sessions", symbol: "calendar.badge.clock", message: "New bookings show up here the moment artists book.")
            }
            ForEach(model.upcoming.prefix(5)) { booking in
                NavigationLink(value: booking) { BookingRow(booking: booking, perspective: .studioOwner).glassCard(padding: 12) }
                    .buttonStyle(PressableCardStyle())
                    .scrollReveal()
            }
        }
    }

    private var manage: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Manage")
            VStack(spacing: 0) {
                ManageLink(title: "Earnings & payouts", symbol: "chart.bar.fill", colors: TilePalette.mint) {
                    EarningsView(studio: studio, bookings: model.bookings, payouts: model.payouts, fees: model.fees)
                }
                Divider().padding(.leading, 60)
                ManageLink(title: "Past bookings", symbol: "clock.arrow.circlepath", colors: TilePalette.ocean) {
                    StudioBookingListView(title: "Past bookings", bookings: model.past)
                }
                Divider().padding(.leading, 60)
                ManageLink(title: "Prices & services", symbol: "tag.fill", colors: TilePalette.signal) {
                    StudioSectionEditor(title: "Prices & services") { StudioPricingEditor(studio: $0) }
                }
                Divider().padding(.leading, 60)
                ManageLink(title: "Opening hours", symbol: "clock.fill", colors: TilePalette.violet) {
                    StudioSectionEditor(title: "Opening hours") { OpeningHoursEditor(hours: $0.openingHours) }
                }
                Divider().padding(.leading, 60)
                ManageLink(title: "Reviews", symbol: "star.bubble.fill", colors: [Theme.warning, Theme.accent], badge: model.reviews.count) {
                    ReviewsListView(studio: studio, reviews: model.reviews, canReply: true)
                }
            }
            .glassCard(padding: 0)
        }
    }
}

/// Neon card with this month's earnings and a six-month trend line.
private struct EarningsHeroCard: View {
    let studio: Studio
    let summary: EarningsSummary

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Earned this month").font(.subheadline.weight(.semibold)).opacity(0.85)
                Spacer()
                Image(systemName: "waveform").font(.subheadline.weight(.bold)).opacity(0.8)
            }
            Text(Money.format(summary.netThisMonth, currency: studio.currency))
                .font(.system(size: 40, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Chart(summary.monthly) { item in
                AreaMark(x: .value("Month", item.month, unit: .month), y: .value("Earnings", Double(item.amount) / 100))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Month", item.month, unit: .month), y: .value("Earnings", Double(item.amount) / 100))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(.white)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 64)
            HStack {
                Label("Next payout \(Money.format(summary.pendingPayout, currency: studio.currency))", systemImage: "arrow.down.circle.fill")
                Spacer()
                Text(L10n.format("%lld%% platform fee", studio.feePercent)).opacity(0.75)
            }
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.neon, in: shape)
        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
        .neonGlow(Theme.magenta, radius: 20)
        .accessibilityElement(children: .combine)
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
    var colors: [Color] = TilePalette.signal
    var badge: Int = 0
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, size: 32, colors: colors)
                Text(localized: title).font(.body.weight(.medium))
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }
}

struct LiveToggleCard: View {
    @Environment(AppState.self) private var app
    let studio: Studio
    @State private var error: String?

    var body: some View {
        Toggle(isOn: Binding(get: { studio.isActive }, set: { newValue in
            Task {
                do {
                    let updated = try await app.backend.setStudioActive(id: studio.id, isActive: newValue)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { app.ownedStudio = updated }
                } catch { self.error = error.userMessage }
            }
        })) {
            HStack(spacing: 12) {
                PulseDot(color: Theme.positive, isActive: studio.isActive)
                    .id(studio.isActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(studio.isActive ? "Live on EasySesh" : "Paused")).font(.headline)
                    Text(LocalizedStringKey(studio.isActive ? "Artists can find and book you." : "Hidden from search. Existing bookings are kept."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(Theme.positive)
        .disabled(studio.status != .approved)
        .glassCard()
        .haptic(.success, trigger: studio.isActive)
        .errorAlert($error)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    var colors: [Color] = TilePalette.signal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconTile(symbol: symbol, size: 30, colors: colors)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 24, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(localized: title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14, cornerRadius: 20)
        .accessibilityElement(children: .combine)
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
        .easyseshGrouped()
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
            EasySeshScreen("Calendar", eyebrow: selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)), refresh: { await load() }) {
                GlassIconButton(symbol: "nosign", label: "Block time") { showBlock = true }
            } content: {
                MonthCalendar(
                    selectedDay: $selectedDay,
                    markedDays: Set(bookings.filter { $0.status.isActive || $0.status == .completed }.map { $0.startsAt.startOfDay }),
                    blockedDays: Set(blocked.map { $0.startsAt.startOfDay })
                )
                if let studio = app.ownedStudio {
                    dayAgenda(studio)
                        .id(selectedDay)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedDay)
            .navigationDestination(for: Booking.self) { BookingDetailView(bookingId: $0.id, initial: $0) }
            .sheet(isPresented: $showBlock) {
                if let studio = app.ownedStudio {
                    BlockTimeSheet(studioId: studio.id, day: selectedDay) { blocked.append($0) }
                }
            }
            .task { await load() }
            .onChange(of: app.pendingDeepLink) { openDeepLink() }
            .errorAlert($error)
        }
    }

    @ViewBuilder private func dayAgenda(_ studio: Studio) -> some View {
        let window = AvailabilityEngine().openingWindow(for: studio, on: selectedDay)
        let dayBookings = bookings.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: selectedDay) && $0.status != .expired }
        let dayBlocks = blocked.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: selectedDay) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GlowSectionHeader(title: selectedDay.formatted(.dateTime.weekday(.wide).day()), count: dayBookings.count)
                if let window {
                    Label("\(window.start.formatted(date: .omitted, time: .shortened))–\(window.end.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                } else {
                    Label("Closed", systemImage: "moon.zzz.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                }
            }
            if dayBookings.isEmpty && dayBlocks.isEmpty {
                GlassEmptyState(title: "Nothing booked", symbol: "sparkles", message: window == nil ? "The studio is closed this day." : "This day is wide open for sessions.")
            }
            ForEach(dayBookings) { booking in
                NavigationLink(value: booking) {
                    HStack(spacing: 12) {
                        Capsule().fill(Theme.neon).frame(width: 4)
                        BookingRow(booking: booking, perspective: .studioOwner)
                    }
                    .glassCard(padding: 12)
                }
                .buttonStyle(PressableCardStyle())
                .scrollReveal()
            }
            ForEach(dayBlocks) { slot in
                HStack(spacing: 12) {
                    IconTile(symbol: "nosign", size: 34, colors: [Color.red, Theme.magenta])
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.reason.isEmpty ? "Blocked" : slot.reason).font(.subheadline.weight(.semibold))
                        Text("\(slot.startsAt.formatted(date: .omitted, time: .shortened)) – \(slot.endsAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Unblock") { unblock(slot) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .glassCard(padding: 12)
                .scrollReveal()
            }
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
            .easyseshGrouped()
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
    var fees: [FeeLedgerEntry] = []
    @State private var invoices: [FeeInvoice] = []

    var body: some View {
        let summary = EarningsCalculator.summary(bookings: bookings, payouts: payouts, currency: studio.currency)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Earned this month").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(summary.netThisMonth, currency: studio.currency)).font(.largeTitle.bold())
                    Text(L10n.format("%@ booked · %lld%% platform fee", Money.format(summary.grossThisMonth, currency: studio.currency), studio.feePercent))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Chart(summary.monthly) { item in
                    BarMark(x: .value("Month", item.month, unit: .month), y: .value("Earnings", Double(item.amount) / 100))
                        .foregroundStyle(Theme.accent)
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
                            Text(payout.status == .paid ? L10n.format("Paid %@", (payout.paidAt ?? payout.scheduledFor).formatted(date: .abbreviated, time: .omitted)) : L10n.format("Expected %@", payout.scheduledFor.formatted(date: .abbreviated, time: .omitted)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(text: payout.status.title, color: payout.status == .paid ? Theme.positive : payout.status == .failed ? Color.red : Theme.warning)
                    }
                }
            }

            Section {
                let owed = fees.reduce(0) { $0 + $1.amount }
                InfoRow(symbol: "banknote", title: "Platform fees owed", value: Money.format(max(owed, 0), currency: studio.currency))
                ForEach(fees) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(localized: entry.kind.title)
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.format(entry.amount, currency: entry.currency))
                            .foregroundStyle(entry.amount < 0 ? Theme.positive : Color.primary)
                    }
                }
            } header: {
                Text("Cash bookings & platform fees")
            } footer: {
                Text(L10n.format("For cash bookings you collect the full price; EasySesh's %lld%% fee is deducted from your next payout. Anything left is invoiced monthly and must be paid within 14 days. Unpaid invoices lead to suspension from EasySesh and debt collection.", studio.feePercent))
            }

            if !invoices.isEmpty {
                Section {
                    ForEach(invoices) { invoice in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Money.format(invoice.amount, currency: invoice.currency)).font(.headline)
                                if let due = invoice.dueAt {
                                    Text("Due \(due.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                                        .foregroundStyle(invoice.isOverdue ? Color.red : Color.secondary)
                                }
                            }
                            Spacer()
                            if let link = invoice.hostedInvoiceUrl, let url = URL(string: link), invoice.status != "paid" {
                                Link("Pay", destination: url).font(.subheadline.weight(.bold))
                            }
                            StatusPill(text: invoice.statusTitle, color: invoice.status == "paid" ? Theme.positive : (invoice.isOverdue || invoice.isInCollections) ? Color.red : Theme.warning)
                        }
                    }
                } header: {
                    Text("Invoices")
                } footer: {
                    if invoices.contains(where: { $0.isOverdue || $0.isInCollections }) {
                        Text("You have an overdue invoice. Pay it now to avoid suspension and debt collection. Contact support if you think this is a mistake.")
                            .foregroundStyle(Color.red)
                    }
                }
            }

            Section {
                NavigationLink { PayoutAccountEditor(studioId: studio.id) } label: { Label("Payout details", systemImage: "building.columns") }
                NavigationLink { LegalDocumentView(document: .studioAgreement) } label: { Label("Studio agreement", systemImage: "doc.text") }
            }
        }
        .easyseshGrouped()
        .navigationTitle("Earnings")
        .task { invoices = (try? await app.backend.feeInvoices(studioId: studio.id)) ?? invoices }
    }
}

// MARK: - Studio settings tab

struct StudioSettingsView: View {
    @Environment(AppState.self) private var app

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            EasySeshScreen("Studio", eyebrow: "Your listing", refresh: { app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio }) {
                if let studio = app.ownedStudio {
                    cover(studio)
                    quickStats(studio)
                    LazyVGrid(columns: columns, spacing: 12) {
                        tile("Edit profile", "Photos, gear, rooms", "pencil", TilePalette.signal) { StudioEditorView(studio: studio, isApplication: false) }
                        tile("Prices", "Sessions & add-ons", "tag.fill", TilePalette.violet) {
                            StudioSectionEditor(title: "Prices & services") { StudioPricingEditor(studio: $0) }
                        }
                        tile("Opening hours", "When you're bookable", "clock.fill", TilePalette.ocean) {
                            StudioSectionEditor(title: "Opening hours") { OpeningHoursEditor(hours: $0.openingHours) }
                        }
                        tile("Booking settings", studio.bookingPolicy.instantBook ? "Instant booking" : "You approve (24h)", "bolt.fill", [Theme.warning, Theme.accent]) {
                            StudioSectionEditor(title: "Booking settings") { StudioPolicyEditor(studio: $0) }
                        }
                        tile("Promote", studio.isPromoted ? "Promoted now" : "Top of search", "megaphone.fill", TilePalette.signal) { PromotionView(studio: studio) }
                        tile("Artist profile", "Connect yours", "link", TilePalette.violet) { StudioArtistLinkView(studio: studio) }
                        tile("Payouts", "Bank details", "building.columns.fill", TilePalette.mint) { PayoutAccountEditor(studioId: studio.id) }
                        tile("Account", "Notifications & data", "person.crop.circle.fill", TilePalette.muted) { SettingsView() }
                        tile("App settings", "Language, look, storage", "slider.horizontal.3", TilePalette.ocean) { AppSettingsView() }
                        tile("Support", "Talk to EasySesh", "questionmark.bubble.fill", [Theme.warning, Theme.accent]) { SupportCenterView() }
                        tile("Agreement", "Studio terms", "doc.text.fill", TilePalette.muted) { LegalDocumentView(document: .studioAgreement) }
                    }
                } else {
                    NavigationLink { SettingsView() } label: { Label("Account & notifications", systemImage: "gearshape").glassCard() }
                        .buttonStyle(PressableCardStyle())
                }
                SignOutButton()
            }
        }
    }

    private func cover(_ studio: Studio) -> some View {
        NavigationLink { StudioDetailView(studioId: studio.id, initial: studio) } label: {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { RemoteImage(url: studio.photoUrls.first) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            PulseDot(color: Theme.positive, isActive: studio.isActive)
                            Text(localized: studio.isActive ? "Live" : studio.status.title).font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.8)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        if studio.isPromoted { PromotedTag() }
                        HStack(spacing: 6) {
                            Text(studio.name).font(.title2.weight(.heavy)).lineLimit(1)
                            if studio.isVerified { VerifiedBadge() }
                            if studio.showsAdminBadge { AdminBadge() }
                        }
                        Text(studio.address.publicArea).font(.subheadline).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    Label("Preview", systemImage: "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(12)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.glassEdge, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .buttonStyle(PressableCardStyle())
    }

    private func quickStats(_ studio: Studio) -> some View {
        HStack(spacing: 0) {
            stat(studio.reviewCount == 0 ? "–" : String(format: "%.1f", studio.ratingAverage), "Rating")
            Divider().frame(height: 30)
            stat("\(studio.reviewCount)", "Reviews")
            Divider().frame(height: 30)
            stat("\(studio.bookingCount)", "Bookings")
            Divider().frame(height: 30)
            stat(Money.format(studio.priceFrom, currency: studio.currency), "From / h")
        }
        .glassCard(padding: 12)
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(localized: title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tile<Destination: View>(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String, _ colors: [Color], @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 14) {
                IconTile(symbol: symbol, size: 38, colors: colors)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14, cornerRadius: 20)
        }
        .buttonStyle(PressableCardStyle())
        .scrollReveal()
    }
}
