import XCTest
import CoreLocation
@testable import Sonora

/// Fixtures match supabase/functions/_shared/pricing_test.ts so client and server agree on every price.
final class PricingTests: XCTestCase {
    private func studio(deposit: Int = 0) -> Studio {
        var studio = Studio.newDraft(ownerId: UUID())
        studio.currency = "EUR"
        studio.sessionTypes = [SessionType(id: "rec", name: "Recording", details: "", hourlyRate: 2500, minimumHours: 2, includesEngineer: false)]
        studio.addOns = [
            ServiceAddOn(id: "mixing", kind: .mixing, name: "Mixing", price: 7500, unit: .perTrack),
            ServiceAddOn(id: "producer", kind: .producer, name: "Producer", price: 2500, unit: .perHour),
        ]
        studio.bookingPolicy.depositPercent = deposit
        return studio.normalized()
    }

    func testQuoteWithoutAddOns() {
        let s = studio()
        let price = PricingEngine.quote(studio: s, sessionType: s.sessionTypes[0], hours: 3)
        XCTAssertEqual(price.subtotal, 7500)
        XCTAssertEqual(price.serviceFee, 0)
        XCTAssertEqual(price.total, 7500)
        XCTAssertEqual(price.dueNow, 7500)
        XCTAssertEqual(price.studioCommission, 750) // 10% platform fee
        XCTAssertEqual(price.studioPayout, 6750)
        XCTAssertEqual(price.platformRevenue, 750)
    }

    func testQuoteWithAddOnsAndDeposit() {
        let s = studio(deposit: 30)
        let price = PricingEngine.quote(studio: s, sessionType: s.sessionTypes[0], hours: 2, addOns: ["mixing": 2, "producer": 1])
        XCTAssertEqual(price.sessionAmount, 5000)
        XCTAssertEqual(price.addOnsAmount, 20000)
        XCTAssertEqual(price.subtotal, 25000)
        XCTAssertEqual(price.serviceFee, 0)
        XCTAssertEqual(price.depositAmount, 7500)
        XCTAssertEqual(price.dueNow, 7500)
        XCTAssertEqual(price.dueLater, 17500)
        XCTAssertEqual(price.studioCommission, 2500)
    }

    func testPriceFromIsLowestSessionRate() {
        var s = studio()
        s.sessionTypes.append(SessionType(id: "cheap", name: "Rehearsal", details: "", hourlyRate: 1200, minimumHours: 1, includesEngineer: false))
        XCTAssertEqual(s.normalized().priceFrom, 1200)
    }

    func testRefundPolicies() {
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .flexible, hoursUntilStart: 25), 100)
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .flexible, hoursUntilStart: 23), 0)
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .moderate, hoursUntilStart: 80), 100)
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .moderate, hoursUntilStart: 30), 50)
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .strict, hoursUntilStart: 24 * 8), 50)
        XCTAssertEqual(RefundCalculator.refundPercent(policy: .strict, hoursUntilStart: 24 * 6), 0)

        let s = studio()
        let price = PricingEngine.quote(studio: s, sessionType: s.sessionTypes[0], hours: 3)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(30 * 3600)
        XCTAssertEqual(RefundCalculator.refundAmount(price: price, amountPaid: price.total, policy: .moderate, startsAt: start, cancelledBy: .artist, now: now), 3750)
        XCTAssertEqual(RefundCalculator.refundAmount(price: price, amountPaid: price.total, policy: .strict, startsAt: start, cancelledBy: .studioOwner, now: now), 7500)
    }

    func testMoneyParsing() {
        XCTAssertEqual(Money.parse("15"), 1500)
        XCTAssertEqual(Money.parse("15,50"), 1550)
        XCTAssertEqual(Money.parse("15.5"), 1550)
        XCTAssertNil(Money.parse("abc"))
        XCTAssertEqual(Money.percent(7500, 10), 750)
    }

    func testCashOnlyWithoutDeposit() {
        XCTAssertTrue(PricingEngine.acceptsCash(studio()))
        XCTAssertFalse(PricingEngine.acceptsCash(studio(deposit: 30)))
        var noCash = studio()
        noCash.bookingPolicy.acceptsCash = false
        XCTAssertFalse(PricingEngine.acceptsCash(noCash))
    }

    func testPasswordPolicy() {
        XCTAssertNotNil(PasswordPolicy.problem("short1A"))
        XCTAssertNotNil(PasswordPolicy.problem("alllowercase123"))
        XCTAssertNil(PasswordPolicy.problem("Studio2026ok"))
    }
}

final class AvailabilityTests: XCTestCase {
    private func studio() -> Studio {
        var studio = Studio.newDraft(ownerId: UUID())
        studio.timezone = "Europe/Athens"
        studio.status = .approved
        studio.isActive = true
        studio.openingHours = [
            OpeningHours(weekday: 2, isClosed: false, opensAt: 600, closesAt: 1320), // Monday 10–22
            OpeningHours(weekday: 6, isClosed: false, opensAt: 720, closesAt: 1560), // Friday 12–02
        ]
        studio.bookingPolicy = BookingPolicy(instantBook: true, cancellationPolicy: .moderate, depositPercent: 0, minimumNoticeHours: 0, maxAdvanceDays: 365, bufferMinutes: 0, terms: "")
        return studio
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    func testSlotsRespectOpeningHoursAndBookings() {
        let engine = AvailabilityEngine()
        let monday = date("2026-10-05T09:00:00Z") // 12:00 in Athens
        let now = date("2026-10-01T00:00:00Z")
        let all = engine.availableSlots(for: studio(), on: monday, hours: 2, busy: [], now: now)
        XCTAssertEqual(all.count, 11) // 10:00 … 20:00 starts
        XCTAssertEqual(all.first?.start, date("2026-10-05T07:00:00Z"))

        let booked = DateInterval(start: date("2026-10-05T09:00:00Z"), end: date("2026-10-05T12:00:00Z")) // 12–15 local
        let free = engine.availableSlots(for: studio(), on: monday, hours: 2, busy: [booked], now: now)
        XCTAssertFalse(free.contains { $0.start == date("2026-10-05T08:00:00Z") }) // 11–13 overlaps
        XCTAssertTrue(free.contains { $0.start == date("2026-10-05T07:00:00Z") }) // 10–12 touches, allowed
        XCTAssertTrue(free.contains { $0.start == date("2026-10-05T12:00:00Z") }) // 15–17
    }

    func testClosedDayHasNoSlots() {
        let tuesday = date("2026-10-06T09:00:00Z")
        XCTAssertTrue(AvailabilityEngine().availableSlots(for: studio(), on: tuesday, hours: 1, busy: [], now: date("2026-10-01T00:00:00Z")).isEmpty)
    }

    func testCanBookPastMidnightInPreviousDaysWindow() {
        let now = date("2026-10-01T00:00:00Z")
        // Saturday 01:00 Athens belongs to Friday's 12:00–02:00 window.
        XCTAssertTrue(AvailabilityEngine().canBook(studio(), start: date("2026-10-09T22:00:00Z"), hours: 1, busy: [], now: now))
        XCTAssertFalse(AvailabilityEngine().canBook(studio(), start: date("2026-10-09T22:00:00Z"), hours: 2, busy: [], now: now))
    }

    func testMinimumNotice() {
        var s = studio()
        s.bookingPolicy.minimumNoticeHours = 48
        let now = date("2026-10-04T12:00:00Z")
        XCTAssertTrue(AvailabilityEngine().availableSlots(for: s, on: date("2026-10-05T09:00:00Z"), hours: 2, busy: [], now: now).isEmpty)
    }
}

final class SearchTests: XCTestCase {
    func testFiltersAndSorting() {
        let studios = MockData.studios()
        let athens = CLLocation(latitude: 37.9838, longitude: 23.7275)
        let engine = SearchEngine()

        let nearest = engine.search(studios: studios, filters: SearchFilters(), sort: .nearest, origin: athens)
        XCTAssertEqual(nearest.count, studios.count)
        XCTAssertLessThanOrEqual(nearest[0].distance ?? 0, nearest[1].distance ?? 0)

        let cheapest = engine.search(studios: studios, filters: SearchFilters(), sort: .cheapest, origin: athens)
        XCTAssertEqual(cheapest.first?.studio.name, "Psyri Records")

        var filters = SearchFilters()
        filters.maxDistanceKm = 5
        let nearby = engine.search(studios: studios, filters: filters, sort: .nearest, origin: athens)
        XCTAssertTrue(nearby.allSatisfy { ($0.distance ?? 0) <= 5000 })
        XCTAssertFalse(nearby.contains { $0.studio.address.city == "Copenhagen" })

        filters = SearchFilters()
        filters.equipmentQuery = "u87"
        XCTAssertTrue(engine.search(studios: studios, filters: filters, sort: .topRated, origin: nil).allSatisfy { studio in
            studio.studio.equipment.contains { $0.name.lowercased().contains("u87") }
        })

        filters = SearchFilters()
        filters.facilities = [.podcastSetup]
        XCTAssertEqual(engine.search(studios: studios, filters: filters, sort: .nearest, origin: nil).map(\.studio.name), ["Kypseli Podcast House"])

        let summary = engine.areaSummary(results: nearest, areaName: "Athens", radiusKm: 5)
        XCTAssertGreaterThan(summary.studioCount, 0)
        XCTAssertEqual(summary.priceFrom, 1500)
    }

    func testUnapprovedStudiosAreHidden() {
        var studios = MockData.studios()
        studios[0].status = .pendingReview
        studios[1].isActive = false
        let results = SearchEngine().search(studios: studios, filters: SearchFilters(), sort: .nearest, origin: nil)
        XCTAssertEqual(results.count, studios.count - 2)
    }
}

@MainActor
final class MockBackendTests: XCTestCase {
    func testBookingPaymentCancellationFlow() async throws {
        let backend = MockBackend(latency: .zero)
        _ = try await backend.signIn(email: "artist@demo.sonora", password: MockData.demoPassword)
        let studio = try await backend.studio(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!) // instant book, flexible
        let engine = AvailabilityEngine()
        var slot: TimeSlot?
        for offset in 3..<20 where slot == nil {
            let day = Date.now.adding(days: offset)
            let busy = try await backend.busyIntervals(studioIds: [studio.id], from: day.adding(days: -1), to: day.adding(days: 2))
            slot = engine.availableSlots(for: studio, on: day, hours: 2, busy: busy[studio.id] ?? []).first
        }
        let start = try XCTUnwrap(slot).start

        let request = BookingRequest(studio: studio, sessionType: studio.sessionTypes[0], startsAt: start, hours: 2, addOns: [:], notes: "")
        let booking = try await backend.createBooking(request)
        XCTAssertEqual(booking.status, .awaitingPayment)

        // Same slot can't be taken twice.
        do {
            _ = try await backend.createBooking(request)
            XCTFail("Double booking should fail")
        } catch {
            XCTAssertEqual(error as? BackendError, .slotUnavailable)
        }

        let confirmed = try await backend.confirmPayment(bookingId: booking.id, method: .applePay)
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.paymentStatus, .paid)

        let cancelled = try await backend.cancelBooking(id: booking.id, reason: "Test")
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.refundAmount, confirmed.price.total) // flexible, > 24h ahead
        XCTAssertEqual(cancelled.paymentStatus, .refunded)
    }

    func testStudioApplicationNeedsApproval() async throws {
        let backend = MockBackend(latency: .zero)
        let owner = try await backend.signUp(email: "new@studio.io", password: "Password1234", role: .studioOwner)
        var studio = Studio.newDraft(ownerId: owner.id)
        studio = try await backend.saveStudio(studio)
        do {
            _ = try await backend.submitStudioForReview(id: studio.id)
            XCTFail("Incomplete studio should not be submittable")
        } catch {}

        studio.name = "New Studio"
        studio.description = String(repeating: "Great room. ", count: 5)
        studio.photoUrls = ["https://example.com/a.jpg"]
        studio.address = StudioAddress(street: "Main 1", postalCode: "1000", city: "Athens", area: "Plaka", country: "Greece")
        studio.latitude = 37.97
        studio.longitude = 23.73
        studio.contact.email = "a@b.c"
        studio.genres = [.pop]
        studio.status = .approved // must be ignored
        studio = try await backend.saveStudio(studio)
        XCTAssertEqual(studio.status, .draft)

        studio = try await backend.submitStudioForReview(id: studio.id)
        XCTAssertEqual(studio.status, .pendingReview)
        let visible = try await backend.publishedStudios()
        XCTAssertFalse(visible.contains { $0.id == studio.id })

        // No studio tools before approval.
        do {
            _ = try await backend.addBlockedSlot(BlockedSlot(id: UUID(), studioId: studio.id, startsAt: .now, endsAt: .now.adding(hours: 1), reason: ""))
            XCTFail("Unapproved studio must not use studio tools")
        } catch {}

        backend.simulateAdminDecision(studioId: studio.id, approve: true)
        let published = try await backend.publishedStudios()
        XCTAssertTrue(published.contains { $0.id == studio.id })
        _ = try await backend.addBlockedSlot(BlockedSlot(id: UUID(), studioId: studio.id, startsAt: .now, endsAt: .now.adding(hours: 1), reason: ""))
    }

    func testArtistCannotCreateStudio() async throws {
        let backend = MockBackend(latency: .zero)
        let artist = try await backend.signIn(email: "artist@demo.sonora", password: MockData.demoPassword)
        do {
            _ = try await backend.saveStudio(Studio.newDraft(ownerId: artist.id))
            XCTFail("Artists must not be able to create studios")
        } catch {
            XCTAssertEqual(error as? BackendError, .forbidden)
        }
    }

    func testSupportTicketFlow() async throws {
        let backend = MockBackend(latency: .zero)
        _ = try await backend.signIn(email: "artist@demo.sonora", password: MockData.demoPassword)
        let ticket = try await backend.createSupportTicket(subject: "Refund", category: .payment, body: "Where is my refund?", bookingId: nil)
        XCTAssertEqual(ticket.status, .open)
        _ = try await backend.sendSupportMessage(ticketId: ticket.id, body: "Any news?")
        let messages = try await backend.supportMessages(ticketId: ticket.id)
        XCTAssertEqual(messages.map(\.body), ["Where is my refund?", "Any news?"])
        let closed = try await backend.closeSupportTicket(id: ticket.id)
        XCTAssertEqual(closed.status, .closed)
        let tickets = try await backend.supportTickets()
        XCTAssertEqual(tickets.count, 1)
    }

    func testStudioMessageRequestFlow() async throws {
        let backend = MockBackend(latency: .zero)
        let artist = try await backend.signUp(email: "fresh@artist.io", password: "Password1234", role: .artist)
        var profile = ArtistProfile.empty(id: artist.id)
        profile.artistName = "Luna Beats"
        profile.city = "Athens"
        _ = try await backend.saveArtistProfile(profile)
        await backend.signOut()

        _ = try await backend.signIn(email: "studio@demo.sonora", password: MockData.demoPassword)
        let found = try await backend.searchArtists(query: "luna")
        XCTAssertEqual(found.map(\.id), [artist.id])
        let request = try await backend.startConversation(artistId: artist.id, body: "Want to record with us?")
        XCTAssertTrue(request.isPendingRequest)
        await backend.signOut()

        _ = try await backend.signIn(email: "fresh@artist.io", password: "Password1234")
        let conversations = try await backend.conversations()
        XCTAssertEqual(conversations.first?.badgeCount(for: .artist), 0, "Requests don't count towards the badge")
        let declined = try await backend.respondToMessageRequest(conversationId: request.id, accept: false)
        XCTAssertTrue(declined.isDeclined)
        await backend.signOut()

        _ = try await backend.signIn(email: "studio@demo.sonora", password: MockData.demoPassword)
        do {
            _ = try await backend.startConversation(artistId: artist.id, body: "Hello?")
            XCTFail("Declined requests must block the studio")
        } catch {}
    }

    func testCashBookingAccruesPlatformFee() async throws {
        let backend = MockBackend(latency: .zero)
        _ = try await backend.signIn(email: "studio@demo.sonora", password: MockData.demoPassword)
        // Seed data contains a completed cash session: the studio owes 10% of it.
        let ledger = try await backend.feeLedger(studioId: MockData.ownedStudioId)
        let commission = try XCTUnwrap(ledger.first { $0.kind == .cashCommission })
        let booking = try await backend.booking(id: XCTUnwrap(commission.bookingId))
        XCTAssertTrue(booking.isCash)
        XCTAssertEqual(commission.amount, booking.price.subtotal / 10)
        let payouts = try await backend.payouts(studioId: MockData.ownedStudioId)
        XCTAssertFalse(payouts.contains { $0.bookingIds.contains(booking.id) }, "Cash bookings never create payouts")
    }
}

final class PostgresCodingTests: XCTestCase {
    func testDecodesPostgresRows() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","email":"a@b.c","role":"studio_owner","status":"active","is_verified":false,
         "settings":{"push_enabled":false},"created_at":"2026-09-24T10:00:00.123456+00:00","stripe_customer_id":null}
        """
        let account = try PostgresCoding.decoder().decode(UserAccount.self, from: Data(json.utf8))
        XCTAssertEqual(account.role, .studioOwner)
        XCTAssertFalse(account.settings.pushEnabled)
        XCTAssertTrue(account.settings.messages) // missing keys fall back to defaults
        XCTAssertNotNil(PostgresDate.parse("2026-09-24 10:00:00+00"))
        XCTAssertNotNil(PostgresDate.parse("2026-09-24T10:00:00"))
    }

    func testDecodesSupportRows() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","user_id":"22222222-2222-2222-2222-222222222222","subject":"Refund","category":"payment",
         "booking_id":null,"status":"answered","user_unread":1,"admin_unread":0,"last_message_preview":"Sent","last_message_at":"2026-09-26T10:00:00.5+00:00",
         "created_at":"2026-09-26T09:00:00+00:00","closed_at":null}
        """
        let ticket = try PostgresCoding.decoder().decode(SupportTicket.self, from: Data(json.utf8))
        XCTAssertEqual(ticket.category, .payment)
        XCTAssertEqual(ticket.status, .answered)
        XCTAssertEqual(ticket.userUnread, 1)
    }
}
