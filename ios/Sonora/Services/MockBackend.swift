import Foundation

/// In-memory backend used in demo mode (no Supabase keys configured), SwiftUI previews and tests.
/// It enforces the same rules as the database policies and edge functions so the app behaves realistically.
@MainActor
final class MockBackend: Backend {
    let isDemo = true

    /// Called whenever a notification is created for the signed-in user (drives local notifications in demo mode).
    var onNotification: ((AppNotification) -> Void)?

    private(set) var accounts: [UUID: UserAccount] = [:]
    private var passwords: [String: String] = [:]
    private var artistProfiles: [UUID: ArtistProfile] = [:]
    private(set) var studios: [UUID: Studio] = [:]
    private var payoutAccounts: [UUID: PayoutAccount] = [:]
    private var blocked: [UUID: BlockedSlot] = [:]
    private(set) var bookings: [UUID: Booking] = [:]
    private var transactionsById: [UUID: PaymentTransaction] = [:]
    private var payoutsById: [UUID: Payout] = [:]
    private var conversationsById: [UUID: Conversation] = [:]
    private var messagesById: [UUID: ChatMessage] = [:]
    private var reviewsById: [UUID: Review] = [:]
    private var reports: [Report] = []
    private var disputes: [Dispute] = []
    private var notificationsById: [UUID: AppNotification] = [:]
    private var streams: [UUID: [UUID: AsyncStream<ChatMessage>.Continuation]] = [:]
    private var currentUserId: UUID?

    private let availability = AvailabilityEngine()
    private let latency: Duration

    init(seed: Bool = true, latency: Duration = .milliseconds(250)) {
        self.latency = latency
        guard seed else { return }
        for account in MockData.accounts() {
            accounts[account.id] = account
            passwords[account.email] = MockData.demoPassword
        }
        for profile in MockData.artistProfiles() { artistProfiles[profile.id] = profile }
        let seededStudios = MockData.studios()
        for studio in seededStudios { studios[studio.id] = studio }
        payoutAccounts[MockData.ownedStudioId] = PayoutAccount(studioId: MockData.ownedStudioId, accountHolder: "Exarchia Sound Lab IKE", ibanLast4: "4821", stripeAccountId: "acct_demo", payoutsEnabled: true)
        let seededBookings = MockData.bookings(studios: seededStudios)
        for booking in seededBookings {
            bookings[booking.id] = booking
            recordCharge(for: booking, amount: booking.price.total, method: .applePay, at: booking.createdAt)
        }
        for review in MockData.reviews(studios: seededStudios, bookings: seededBookings) { reviewsById[review.id] = review }
        seedConversations()
        seedNotifications()
        advanceTime()
    }

    // MARK: - Helpers

    private func pause() async {
        try? await Task.sleep(for: latency)
    }

    private func requireUser() throws -> UserAccount {
        guard let id = currentUserId, let user = accounts[id] else { throw BackendError.notAuthenticated }
        guard user.status == .active else { throw BackendError.accountSuspended }
        return user
    }

    private func requireOwner(of studioId: UUID) throws -> (UserAccount, Studio) {
        let user = try requireUser()
        guard let studio = studios[studioId] else { throw BackendError.notFound }
        guard studio.ownerId == user.id || user.role == .admin else { throw BackendError.forbidden }
        return (user, studio)
    }

    private func notify(_ userId: UUID, _ kind: NotificationKind, _ title: String, _ body: String, booking: UUID? = nil, conversation: UUID? = nil, studio: UUID? = nil) {
        let note = AppNotification(id: UUID(), userId: userId, kind: kind, title: title, body: body, isRead: false, bookingId: booking, conversationId: conversation, studioId: studio, createdAt: .now)
        notificationsById[note.id] = note
        if userId == currentUserId { onNotification?(note) }
    }

    private func amountPaid(bookingId: UUID) -> Int {
        transactionsById.values
            .filter { $0.bookingId == bookingId && $0.status == .succeeded }
            .reduce(0) { $0 + ($1.kind == .refund ? -$1.amount : $1.amount) }
    }

    @discardableResult
    private func recordCharge(for booking: Booking, amount: Int, method: PaymentMethod, kind: TransactionKind = .charge, at date: Date = .now) -> PaymentTransaction {
        let fee = kind == .charge ? booking.price.serviceFee : 0
        let transaction = PaymentTransaction(
            id: UUID(), bookingId: booking.id, studioId: booking.studioId, artistId: booking.artistId,
            kind: kind, method: method, status: .succeeded, amount: amount, platformFee: fee,
            currency: booking.price.currency, receiptNumber: "RCPT-\(Int.random(in: 100000...999999))",
            cardBrand: method == .card ? "Visa" : nil, cardLast4: method == .card ? "4242" : nil,
            failureReason: nil, providerReference: "pi_demo_\(UUID().uuidString.prefix(8))", createdAt: date
        )
        transactionsById[transaction.id] = transaction
        return transaction
    }

    private func systemMessage(bookingId: UUID, _ text: String) {
        guard let conversation = conversationsById.values.first(where: { $0.bookingId == bookingId }) else { return }
        appendMessage(ChatMessage(id: UUID(), conversationId: conversation.id, senderId: nil, kind: .system, body: text, createdAt: .now))
    }

    private func appendMessage(_ message: ChatMessage) {
        messagesById[message.id] = message
        guard var conversation = conversationsById[message.conversationId] else { return }
        conversation.lastMessagePreview = message.body
        conversation.lastMessageAt = message.createdAt
        let senderIsArtist = message.senderId == conversation.artistId
        if message.senderId == nil || !senderIsArtist { conversation.artistUnread += 1 }
        if message.senderId == nil || senderIsArtist { conversation.studioUnread += 1 }
        conversationsById[conversation.id] = conversation
        streams[conversation.id]?.values.forEach { $0.yield(message) }
    }

    private func ownerId(ofStudio id: UUID) -> UUID? { studios[id]?.ownerId }

    /// Moves time-based state forward: completes past sessions, charges balances, creates payouts, expires unpaid holds.
    private func advanceTime(now: Date = .now) {
        for var booking in bookings.values {
            if booking.status == .awaitingPayment && booking.createdAt.adding(minutes: 30) < now {
                booking.status = .expired
                bookings[booking.id] = booking
                continue
            }
            if booking.status == .pendingApproval && booking.startsAt < now {
                booking.status = .expired
                booking.paymentStatus = .refunded
                bookings[booking.id] = booking
                continue
            }
            guard booking.status == .confirmed, booking.endsAt < now else { continue }
            booking.status = .completed
            if booking.paymentStatus == .depositPaid {
                recordCharge(for: booking, amount: booking.price.dueLater, method: .card, kind: .balance, at: booking.endsAt)
                booking.paymentStatus = .paid
            }
            booking.updatedAt = now
            bookings[booking.id] = booking
            if !booking.hasReview {
                notify(booking.artistId, .reviewReminder, "How was \(booking.studioName)?", "Leave a review for your session.", booking: booking.id, studio: booking.studioId)
            }
        }
        let paidOut = Set(payoutsById.values.flatMap(\.bookingIds))
        for booking in bookings.values where booking.status == .completed && !paidOut.contains(booking.id) {
            let date = booking.endsAt.adding(days: PlatformConfig.payoutDelayDays)
            let payout = Payout(id: UUID(), studioId: booking.studioId, amount: booking.price.studioPayout, currency: booking.price.currency, status: date < now ? .paid : .scheduled, scheduledFor: date, paidAt: date < now ? date : nil, bookingIds: [booking.id])
            payoutsById[payout.id] = payout
        }
    }

    private func seedConversations() {
        guard let booking = bookings.values.first(where: { $0.artistId == MockData.artistUserId && $0.status == .confirmed }),
              let studio = studios[booking.studioId] else { return }
        let conversation = Conversation(id: UUID(), artistId: booking.artistId, studioId: studio.id, bookingId: booking.id, artistName: booking.artistName, studioName: studio.name, studioPhotoUrl: studio.photoUrls.first, lastMessagePreview: "", lastMessageAt: .now, artistUnread: 0, studioUnread: 0)
        conversationsById[conversation.id] = conversation
        let lines: [(UUID?, String, Int)] = [
            (nil, "Booking \(booking.reference) confirmed for \(booking.startsAt.formatted(date: .abbreviated, time: .shortened)).", -180),
            (booking.artistId, "Hi! Can I bring my own guitar for a couple of overdubs?", -120),
            (studio.ownerId, "Of course! We have a Fender Deluxe amp you're welcome to use too 🎸", -95),
        ]
        for (sender, text, minutes) in lines {
            appendMessage(ChatMessage(id: UUID(), conversationId: conversation.id, senderId: sender, kind: sender == nil ? .system : .text, body: text, createdAt: .now.adding(minutes: minutes)))
        }
        conversationsById[conversation.id]?.artistUnread = 1
        conversationsById[conversation.id]?.studioUnread = 0
    }

    private func seedNotifications() {
        let artistBooking = bookings.values.first { $0.artistId == MockData.artistUserId && $0.status == .confirmed }
        notify(MockData.artistUserId, .bookingConfirmed, "Booking confirmed", "Your session at \(artistBooking?.studioName ?? "the studio") is confirmed.", booking: artistBooking?.id)
        notify(MockData.artistUserId, .system, "Welcome to Sonora", "Find a studio, book a session and pay securely in the app.")
        if let request = bookings.values.first(where: { $0.status == .pendingApproval }) {
            notify(MockData.studioOwnerUserId, .bookingRequested, "New booking request", "\(request.artistName) wants to book \(request.hours)h on \(request.startsAt.formatted(date: .abbreviated, time: .shortened)).", booking: request.id)
        }
        notify(MockData.studioOwnerUserId, .newReview, "New 5★ review", "Nova Lykke reviewed Exarchia Sound Lab.", studio: MockData.ownedStudioId)
    }

    // MARK: - Demo-only controls

    /// Stands in for the admin dashboard in demo mode.
    func simulateAdminDecision(studioId: UUID, approve: Bool, note: String? = nil) {
        guard var studio = studios[studioId] else { return }
        studio.status = approve ? .approved : .changesRequested
        studio.isActive = approve
        studio.isVerified = approve
        studio.adminNote = note
        studios[studioId] = studio
        if approve {
            notify(studio.ownerId, .studioApproved, "Your studio is live 🎉", "\(studio.name) was approved and is now visible to artists.", studio: studioId)
        } else {
            notify(studio.ownerId, .studioChangesRequested, "Changes requested", note ?? "Please update your listing and resubmit.", studio: studioId)
        }
    }

    // MARK: - Auth

    func restoreSession() async -> UserAccount? {
        currentUserId.flatMap { accounts[$0] }
    }

    func signUp(email: String, password: String, role: UserRole) async throws -> UserAccount {
        await pause()
        let email = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard email.contains("@"), email.contains(".") else { throw BackendError.validation("Enter a valid email address.") }
        guard password.count >= 8 else { throw BackendError.validation("Use at least 8 characters for your password.") }
        guard role != .admin else { throw BackendError.forbidden }
        guard passwords[email] == nil else { throw BackendError.emailInUse }
        let account = UserAccount(id: UUID(), email: email, role: role, status: .active, isVerified: false, settings: UserSettings(), createdAt: .now)
        accounts[account.id] = account
        passwords[email] = password
        if role == .artist { artistProfiles[account.id] = .empty(id: account.id) }
        currentUserId = account.id
        return account
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        await pause()
        let email = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard passwords[email] == password, let account = accounts.values.first(where: { $0.email == email }) else {
            throw BackendError.invalidCredentials
        }
        guard account.status == .active else { throw BackendError.accountSuspended }
        currentUserId = account.id
        advanceTime()
        return account
    }

    func signInWithApple(idToken: String, nonce: String, role: UserRole) async throws -> UserAccount {
        await pause()
        return try socialSignIn(role: role)
    }

    func signInWithGoogle(role: UserRole) async throws -> UserAccount {
        await pause()
        return try socialSignIn(role: role)
    }

    private func socialSignIn(role: UserRole) throws -> UserAccount {
        let id = role == .studioOwner ? MockData.studioOwnerUserId : MockData.artistUserId
        guard let account = accounts[id] else { throw BackendError.notFound }
        currentUserId = id
        return account
    }

    func sendPasswordReset(email: String) async throws {
        await pause()
    }

    func signOut() async {
        currentUserId = nil
    }

    func deleteAccount() async throws {
        let user = try requireUser()
        accounts[user.id] = nil
        passwords[user.email] = nil
        artistProfiles[user.id] = nil
        currentUserId = nil
    }

    func updateSettings(_ settings: UserSettings) async throws -> UserAccount {
        var user = try requireUser()
        user.settings = settings
        accounts[user.id] = user
        return user
    }

    // MARK: - Profiles

    func artistProfile(id: UUID) async throws -> ArtistProfile? {
        await pause()
        return artistProfiles[id]
    }

    func saveArtistProfile(_ profile: ArtistProfile) async throws -> ArtistProfile {
        await pause()
        let user = try requireUser()
        guard user.id == profile.id else { throw BackendError.forbidden }
        guard !profile.artistName.trimmingCharacters(in: .whitespaces).isEmpty else { throw BackendError.validation("Artist name is required.") }
        var saved = profile
        saved.isVerified = artistProfiles[profile.id]?.isVerified ?? false // only admins verify
        artistProfiles[profile.id] = saved
        return saved
    }

    func uploadImage(_ data: Data, folder: String) async throws -> String {
        await pause()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url.absoluteString
    }

    // MARK: - Studios

    func publishedStudios() async throws -> [Studio] {
        await pause()
        return studios.values.filter(\.isBookable).sorted { $0.name < $1.name }
    }

    func studio(id: UUID) async throws -> Studio {
        guard let studio = studios[id] else { throw BackendError.notFound }
        if !studio.isBookable {
            let user = try? requireUser()
            guard user?.id == studio.ownerId || user?.role == .admin else { throw BackendError.notFound }
        }
        return studio
    }

    func ownedStudio() async throws -> Studio? {
        await pause()
        let user = try requireUser()
        return studios.values.first { $0.ownerId == user.id }
    }

    func saveStudio(_ studio: Studio) async throws -> Studio {
        await pause()
        let user = try requireUser()
        guard user.role == .studioOwner || user.role == .admin else { throw BackendError.forbidden }
        if let existing = studios[studio.id] {
            guard existing.ownerId == user.id || user.role == .admin else { throw BackendError.forbidden }
        } else if studios.values.contains(where: { $0.ownerId == user.id }) {
            throw BackendError.validation("You already have a studio.")
        }
        var saved = studio.normalized()
        let existing = studios[studio.id]
        // Owners cannot change moderation fields.
        saved.status = existing?.status ?? .draft
        saved.isVerified = existing?.isVerified ?? false
        saved.adminNote = existing?.adminNote
        saved.ratingAverage = existing?.ratingAverage ?? 0
        saved.reviewCount = existing?.reviewCount ?? 0
        saved.bookingCount = existing?.bookingCount ?? 0
        if saved.status != .approved { saved.isActive = false }
        studios[saved.id] = saved
        return saved
    }

    func submitStudioForReview(id: UUID) async throws -> Studio {
        await pause()
        var (_, studio) = try requireOwner(of: id)
        if let problem = StudioValidator.problems(in: studio).first { throw BackendError.validation(problem) }
        guard [.draft, .changesRequested, .rejected].contains(studio.status) else { return studio }
        studio.status = .pendingReview
        studio.submittedAt = .now
        studios[id] = studio
        return studio
    }

    func setStudioActive(id: UUID, isActive: Bool) async throws -> Studio {
        var (_, studio) = try requireOwner(of: id)
        guard studio.status == .approved else { throw BackendError.validation("Your studio must be approved before it can go live.") }
        studio.isActive = isActive
        studios[id] = studio
        return studio
    }

    func payoutAccount(studioId: UUID) async throws -> PayoutAccount? {
        _ = try requireOwner(of: studioId)
        return payoutAccounts[studioId]
    }

    func savePayoutAccount(_ account: PayoutAccount, iban: String?) async throws -> PayoutAccount {
        await pause()
        _ = try requireOwner(of: account.studioId)
        var saved = account
        if let iban {
            let cleaned = iban.replacingOccurrences(of: " ", with: "").uppercased()
            guard cleaned.count >= 15, cleaned.prefix(2).allSatisfy(\.isLetter) else { throw BackendError.validation("Enter a valid IBAN.") }
            saved.ibanLast4 = String(cleaned.suffix(4))
        }
        saved.payoutsEnabled = !saved.ibanLast4.isEmpty && !saved.accountHolder.isEmpty
        payoutAccounts[account.studioId] = saved
        return saved
    }

    func payoutOnboardingURL(studioId: UUID) async throws -> URL? { nil }

    func busyIntervals(studioIds: [UUID], from: Date, to: Date) async throws -> [UUID: [DateInterval]] {
        let range = DateInterval(start: from, end: max(from, to))
        var result: [UUID: [DateInterval]] = [:]
        for booking in bookings.values where studioIds.contains(booking.studioId) {
            guard booking.status.isActive || booking.status == .awaitingPayment, AvailabilityEngine.overlaps(booking.interval, range) else { continue }
            result[booking.studioId, default: []].append(booking.interval)
        }
        for slot in blocked.values where studioIds.contains(slot.studioId) && AvailabilityEngine.overlaps(slot.interval, range) {
            result[slot.studioId, default: []].append(slot.interval)
        }
        return result
    }

    func blockedSlots(studioId: UUID) async throws -> [BlockedSlot] {
        _ = try requireOwner(of: studioId)
        return blocked.values.filter { $0.studioId == studioId }.sorted { $0.startsAt < $1.startsAt }
    }

    func addBlockedSlot(_ slot: BlockedSlot) async throws -> BlockedSlot {
        _ = try requireOwner(of: slot.studioId)
        guard slot.endsAt > slot.startsAt else { throw BackendError.validation("End time must be after start time.") }
        blocked[slot.id] = slot
        return slot
    }

    func removeBlockedSlot(id: UUID) async throws {
        guard let slot = blocked[id] else { return }
        _ = try requireOwner(of: slot.studioId)
        blocked[id] = nil
    }

    // MARK: - Bookings

    func createBooking(_ request: BookingRequest) async throws -> Booking {
        await pause()
        let user = try requireUser()
        guard user.role == .artist else { throw BackendError.validation("Only artist accounts can book sessions.") }
        guard let studio = studios[request.studio.id], studio.isBookable,
              let type = studio.sessionType(id: request.sessionType.id) else { throw BackendError.notFound }
        guard request.hours >= type.minimumHours else { throw BackendError.validation("Minimum \(type.minimumHours) hours for \(type.name).") }
        guard request.hours <= PlatformConfig.maxSessionHours else { throw BackendError.validation("Sessions can be at most \(PlatformConfig.maxSessionHours) hours.") }

        let busy = try await busyIntervals(studioIds: [studio.id], from: request.startsAt.adding(days: -1), to: request.startsAt.adding(days: 2))
        guard availability.canBook(studio, start: request.startsAt, hours: request.hours, busy: busy[studio.id] ?? []) else {
            throw BackendError.slotUnavailable
        }

        let price = PricingEngine.quote(studio: studio, sessionType: type, hours: request.hours, addOns: request.addOns)
        let profile = artistProfiles[user.id]
        let booking = Booking(
            id: UUID(), reference: BookingReference.make(), artistId: user.id, studioId: studio.id,
            artistName: profile?.artistName.isEmpty == false ? profile!.artistName : user.email,
            studioName: studio.name, sessionTypeId: type.id, sessionTypeName: type.name,
            startsAt: request.startsAt, endsAt: request.startsAt.adding(hours: request.hours), hours: request.hours,
            addOns: PricingEngine.bookedAddOns(studio: studio, selected: request.addOns, hours: request.hours),
            status: .awaitingPayment, paymentStatus: .unpaid, price: price, notes: request.notes,
            cancellationReason: nil, cancelledBy: nil, refundAmount: 0, hasReview: false, createdAt: .now, updatedAt: .now
        )
        bookings[booking.id] = booking
        return booking
    }

    func preparePayment(bookingId: UUID, method: PaymentMethod) async throws -> PaymentIntentInfo {
        await pause()
        let user = try requireUser()
        guard let booking = bookings[bookingId], booking.artistId == user.id else { throw BackendError.notFound }
        guard booking.status == .awaitingPayment else { throw BackendError.validation("This booking is no longer awaiting payment.") }
        let studio = studios[booking.studioId]
        return PaymentIntentInfo(bookingId: bookingId, clientSecret: "pi_demo_secret", customerId: nil, ephemeralKey: nil, amount: booking.price.dueNow, currency: booking.price.currency, captureLater: studio?.bookingPolicy.instantBook == false)
    }

    func confirmPayment(bookingId: UUID, method: PaymentMethod) async throws -> Booking {
        await pause()
        let user = try requireUser()
        guard var booking = bookings[bookingId], booking.artistId == user.id else { throw BackendError.notFound }
        guard booking.status == .awaitingPayment, let studio = studios[booking.studioId] else { return booking }

        if studio.bookingPolicy.instantBook {
            recordCharge(for: booking, amount: booking.price.dueNow, method: method)
            booking.status = .confirmed
            booking.paymentStatus = booking.price.depositAmount > 0 ? .depositPaid : .paid
            notify(user.id, .bookingConfirmed, "Booking confirmed ✅", "\(studio.name) · \(booking.startsAt.formatted(date: .abbreviated, time: .shortened))", booking: booking.id)
            notify(studio.ownerId, .bookingRequested, "New booking", "\(booking.artistName) booked \(booking.hours)h on \(booking.startsAt.formatted(date: .abbreviated, time: .shortened)).", booking: booking.id)
        } else {
            booking.status = .pendingApproval
            booking.paymentStatus = .authorized
            notify(studio.ownerId, .bookingRequested, "New booking request", "\(booking.artistName) wants to book \(booking.hours)h on \(booking.startsAt.formatted(date: .abbreviated, time: .shortened)). Accept or decline.", booking: booking.id)
        }
        booking.updatedAt = .now
        bookings[booking.id] = booking
        var updatedStudio = studio
        updatedStudio.bookingCount += 1
        studios[studio.id] = updatedStudio
        return booking
    }

    func booking(id: UUID) async throws -> Booking {
        let user = try requireUser()
        guard let booking = bookings[id] else { throw BackendError.notFound }
        guard booking.artistId == user.id || ownerId(ofStudio: booking.studioId) == user.id || user.role == .admin else { throw BackendError.forbidden }
        return booking
    }

    func artistBookings() async throws -> [Booking] {
        await pause()
        let user = try requireUser()
        advanceTime()
        return bookings.values.filter { $0.artistId == user.id && $0.status != .awaitingPayment }.sorted { $0.startsAt > $1.startsAt }
    }

    func studioBookings(studioId: UUID) async throws -> [Booking] {
        await pause()
        _ = try requireOwner(of: studioId)
        advanceTime()
        return bookings.values.filter { $0.studioId == studioId && $0.status != .awaitingPayment }.sorted { $0.startsAt > $1.startsAt }
    }

    func cancelBooking(id: UUID, reason: String) async throws -> Booking {
        await pause()
        let user = try requireUser()
        guard var booking = bookings[id], let studio = studios[booking.studioId] else { throw BackendError.notFound }
        let role: UserRole
        if booking.artistId == user.id { role = .artist } else if studio.ownerId == user.id { role = .studioOwner } else { throw BackendError.forbidden }
        guard booking.canCancel else { throw BackendError.validation("This booking can no longer be cancelled.") }

        if booking.paymentStatus == .authorized {
            // Not captured yet: release the hold in full.
            booking.refundAmount = booking.price.dueNow
            booking.paymentStatus = .refunded
        } else {
            let paid = amountPaid(bookingId: id)
            let refund = RefundCalculator.refundAmount(price: booking.price, amountPaid: paid, policy: studio.bookingPolicy.cancellationPolicy, startsAt: booking.startsAt, cancelledBy: role)
            if refund > 0 {
                var transaction = recordCharge(for: booking, amount: refund, method: .card, kind: .refund)
                transaction.platformFee = 0
                transactionsById[transaction.id] = transaction
            }
            booking.refundAmount = refund
            booking.paymentStatus = refund == 0 ? booking.paymentStatus : (refund >= paid ? .refunded : .partiallyRefunded)
        }
        booking.status = .cancelled
        booking.cancelledBy = role
        booking.cancellationReason = reason
        booking.updatedAt = .now
        bookings[id] = booking

        let when = booking.startsAt.formatted(date: .abbreviated, time: .shortened)
        if role == .artist {
            notify(studio.ownerId, .bookingCancelled, "Booking cancelled", "\(booking.artistName) cancelled the session on \(when).", booking: id)
        } else {
            notify(booking.artistId, .bookingCancelled, "Booking cancelled by studio", "\(studio.name) cancelled your session on \(when). You'll get a full refund.", booking: id)
        }
        if booking.refundAmount > 0 {
            notify(booking.artistId, .refundIssued, "Refund on its way", "\(Money.format(booking.refundAmount, currency: booking.price.currency)) will be back on your card in 5–10 days.", booking: id)
        }
        systemMessage(bookingId: id, "Booking \(booking.reference) was cancelled by the \(role == .artist ? "artist" : "studio").")
        return booking
    }

    func rescheduleBooking(id: UUID, newStart: Date) async throws -> Booking {
        await pause()
        let user = try requireUser()
        guard var booking = bookings[id], let studio = studios[booking.studioId] else { throw BackendError.notFound }
        guard booking.artistId == user.id || studio.ownerId == user.id else { throw BackendError.forbidden }
        guard booking.canReschedule else { throw BackendError.validation("This booking can't be changed.") }

        var busy = try await busyIntervals(studioIds: [studio.id], from: newStart.adding(days: -1), to: newStart.adding(days: 2))[studio.id] ?? []
        busy.removeAll { $0 == booking.interval }
        guard availability.canBook(studio, start: newStart, hours: booking.hours, busy: busy) else { throw BackendError.slotUnavailable }

        let old = booking.startsAt.formatted(date: .abbreviated, time: .shortened)
        booking.startsAt = newStart
        booking.endsAt = newStart.adding(hours: booking.hours)
        booking.updatedAt = .now
        bookings[id] = booking
        let new = newStart.formatted(date: .abbreviated, time: .shortened)
        let counterpart = booking.artistId == user.id ? studio.ownerId : booking.artistId
        notify(counterpart, .bookingChanged, "Booking moved", "\(booking.reference) moved from \(old) to \(new).", booking: id)
        systemMessage(bookingId: id, "Booking moved from \(old) to \(new).")
        return booking
    }

    func respondToBooking(id: UUID, accept: Bool, message: String?) async throws -> Booking {
        await pause()
        guard var booking = bookings[id] else { throw BackendError.notFound }
        let (_, studio) = try requireOwner(of: booking.studioId)
        guard booking.status == .pendingApproval else { throw BackendError.validation("This request has already been handled.") }
        if accept {
            recordCharge(for: booking, amount: booking.price.dueNow, method: .card)
            booking.status = .confirmed
            booking.paymentStatus = booking.price.depositAmount > 0 ? .depositPaid : .paid
            notify(booking.artistId, .bookingConfirmed, "Booking confirmed ✅", "\(studio.name) accepted your request for \(booking.startsAt.formatted(date: .abbreviated, time: .shortened)).", booking: id)
        } else {
            booking.status = .declined
            booking.paymentStatus = .refunded
            booking.refundAmount = booking.price.dueNow
            booking.cancellationReason = message
            notify(booking.artistId, .bookingDeclined, "Request declined", "\(studio.name) couldn't take your session. Your card was not charged.\(message.map { " “\($0)”" } ?? "")", booking: id)
        }
        booking.updatedAt = .now
        bookings[id] = booking
        return booking
    }

    func openDispute(bookingId: UUID, reason: String) async throws {
        await pause()
        let user = try requireUser()
        guard var booking = bookings[bookingId] else { throw BackendError.notFound }
        guard booking.artistId == user.id || ownerId(ofStudio: booking.studioId) == user.id else { throw BackendError.forbidden }
        booking.status = .disputed
        bookings[bookingId] = booking
        disputes.append(Dispute(id: UUID(), bookingId: bookingId, openedBy: user.id, reason: reason, status: .open, createdAt: .now))
        notify(user.id, .system, "We're on it", "Our team will review booking \(booking.reference) within 24 hours.", booking: bookingId)
    }

    // MARK: - Payments

    func transactions(bookingId: UUID) async throws -> [PaymentTransaction] {
        _ = try await booking(id: bookingId)
        return transactionsById.values.filter { $0.bookingId == bookingId }.sorted { $0.createdAt < $1.createdAt }
    }

    func payouts(studioId: UUID) async throws -> [Payout] {
        _ = try requireOwner(of: studioId)
        advanceTime()
        return payoutsById.values.filter { $0.studioId == studioId }.sorted { $0.scheduledFor > $1.scheduledFor }
    }

    // MARK: - Chat

    func conversations() async throws -> [Conversation] {
        await pause()
        let user = try requireUser()
        return conversationsById.values
            .filter { $0.artistId == user.id || ownerId(ofStudio: $0.studioId) == user.id }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func conversation(studioId: UUID, bookingId: UUID?) async throws -> Conversation {
        let user = try requireUser()
        guard let studio = studios[studioId] else { throw BackendError.notFound }
        let artistId: UUID
        if user.role == .artist {
            artistId = user.id
        } else if studio.ownerId == user.id, let bookingId, let booking = bookings[bookingId], booking.studioId == studioId {
            // Studios can only start a chat about an existing booking.
            artistId = booking.artistId
        } else {
            throw BackendError.forbidden
        }
        if let existing = conversationsById.values.first(where: { $0.artistId == artistId && $0.studioId == studioId && $0.bookingId == bookingId }) {
            return existing
        }
        let name = artistProfiles[artistId]?.artistName ?? accounts[artistId]?.email ?? "Artist"
        let conversation = Conversation(id: UUID(), artistId: artistId, studioId: studioId, bookingId: bookingId, artistName: name, studioName: studio.name, studioPhotoUrl: studio.photoUrls.first, lastMessagePreview: "", lastMessageAt: .now, artistUnread: 0, studioUnread: 0)
        conversationsById[conversation.id] = conversation
        return conversation
    }

    func messages(conversationId: UUID) async throws -> [ChatMessage] {
        try requireParticipant(conversationId)
        return messagesById.values.filter { $0.conversationId == conversationId }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    private func requireParticipant(_ conversationId: UUID) throws -> (UserAccount, Conversation) {
        let user = try requireUser()
        guard let conversation = conversationsById[conversationId] else { throw BackendError.notFound }
        guard conversation.artistId == user.id || ownerId(ofStudio: conversation.studioId) == user.id else { throw BackendError.forbidden }
        return (user, conversation)
    }

    func sendMessage(conversationId: UUID, body: String) async throws -> ChatMessage {
        let (user, conversation) = try requireParticipant(conversationId)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BackendError.validation("Message is empty.") }
        guard text.count <= 2000 else { throw BackendError.validation("Messages can be at most 2000 characters.") }
        let message = ChatMessage(id: UUID(), conversationId: conversationId, senderId: user.id, kind: .text, body: text, createdAt: .now)
        appendMessage(message)

        let recipient = user.id == conversation.artistId ? ownerId(ofStudio: conversation.studioId) : conversation.artistId
        if let recipient {
            notify(recipient, .newMessage, user.id == conversation.artistId ? conversation.artistName : conversation.studioName, text, conversation: conversationId)
        }
        // Demo: the studio answers artists automatically so the chat feels alive.
        if user.id == conversation.artistId, let ownerId = ownerId(ofStudio: conversation.studioId), ownerId != MockData.studioOwnerUserId || currentUserId != ownerId {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.appendMessage(ChatMessage(id: UUID(), conversationId: conversationId, senderId: ownerId, kind: .text, body: "Thanks for reaching out! We'll get back to you shortly 🎧", createdAt: .now))
            }
        }
        return message
    }

    func markConversationRead(id: UUID) async throws {
        let (user, conversation) = try requireParticipant(id)
        var updated = conversation
        if user.id == conversation.artistId { updated.artistUnread = 0 } else { updated.studioUnread = 0 }
        conversationsById[id] = updated
    }

    func messageStream(conversationId: UUID) -> AsyncStream<ChatMessage> {
        AsyncStream { continuation in
            let token = UUID()
            streams[conversationId, default: [:]][token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.streams[conversationId]?[token] = nil }
            }
        }
    }

    // MARK: - Reviews & moderation

    func reviews(studioId: UUID) async throws -> [Review] {
        await pause()
        return reviewsById.values.filter { $0.studioId == studioId && !$0.isHidden }.sorted { $0.createdAt > $1.createdAt }
    }

    func submitReview(_ review: Review) async throws -> Review {
        await pause()
        let user = try requireUser()
        guard var booking = bookings[review.bookingId], booking.artistId == user.id else { throw BackendError.forbidden }
        guard booking.status == .completed else { throw BackendError.validation("You can review a studio after your session.") }
        guard !booking.hasReview else { throw BackendError.validation("You've already reviewed this session.") }
        guard (1...5).contains(review.rating) else { throw BackendError.validation("Pick 1–5 stars.") }

        var saved = review
        saved.artistId = user.id
        saved.createdAt = .now
        reviewsById[saved.id] = saved
        booking.hasReview = true
        bookings[booking.id] = booking

        if var studio = studios[booking.studioId] {
            let total = studio.ratingAverage * Double(studio.reviewCount) + Double(review.rating)
            studio.reviewCount += 1
            studio.ratingAverage = (total / Double(studio.reviewCount) * 10).rounded() / 10
            studios[studio.id] = studio
            notify(studio.ownerId, .newReview, "New \(review.rating)★ review", "\(review.artistName) reviewed \(studio.name).", studio: studio.id)
        }
        return saved
    }

    func replyToReview(id: UUID, reply: String) async throws -> Review {
        guard var review = reviewsById[id] else { throw BackendError.notFound }
        _ = try requireOwner(of: review.studioId)
        review.studioReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        review.studioRepliedAt = .now
        reviewsById[id] = review
        return review
    }

    func report(target: ReportTarget, targetId: UUID, reason: ReportReason, details: String) async throws {
        await pause()
        let user = try requireUser()
        reports.append(Report(id: UUID(), reporterId: user.id, targetType: target, targetId: targetId, reason: reason, details: details, status: .open, createdAt: .now))
    }

    // MARK: - Notifications

    func notifications() async throws -> [AppNotification] {
        let user = try requireUser()
        advanceTime()
        return notificationsById.values.filter { $0.userId == user.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func markNotificationRead(id: UUID) async throws {
        notificationsById[id]?.isRead = true
    }

    func markAllNotificationsRead() async throws {
        let user = try requireUser()
        for (id, note) in notificationsById where note.userId == user.id { notificationsById[id]?.isRead = true }
    }

    func registerPushToken(_ token: String) async throws {}
}

enum StudioValidator {
    /// Human-readable problems that block submission for review.
    static func problems(in studio: Studio) -> [String] {
        var problems: [String] = []
        if studio.name.trimmingCharacters(in: .whitespaces).count < 3 { problems.append("Add your studio's name.") }
        if studio.description.count < 40 { problems.append("Write a description of at least 40 characters.") }
        if studio.photoUrls.isEmpty { problems.append("Add at least one photo.") }
        if studio.address.street.isEmpty || studio.address.city.isEmpty { problems.append("Add the studio's address.") }
        if studio.latitude == 0 && studio.longitude == 0 { problems.append("Place your studio on the map.") }
        if studio.contact.email.isEmpty && studio.contact.phone.isEmpty { problems.append("Add an email or phone number.") }
        if studio.sessionTypes.isEmpty || studio.sessionTypes.contains(where: { $0.hourlyRate <= 0 }) { problems.append("Set a price for each session type.") }
        if studio.openingHours.allSatisfy(\.isClosed) { problems.append("Set your opening hours.") }
        if studio.genres.isEmpty { problems.append("Pick at least one genre.") }
        return problems
    }
}
