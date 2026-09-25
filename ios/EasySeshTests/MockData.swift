import Foundation
@testable import EasySesh

/// Seed data for demo mode. Mirrors `supabase/seed.sql` so both environments look alike.
enum MockData {
    static let artistUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let studioOwnerUserId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let otherArtistIds = [
        UUID(uuidString: "33333333-3333-3333-3333-333333333331")!,
        UUID(uuidString: "33333333-3333-3333-3333-333333333332")!,
        UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
    ]
    static let ownedStudioId = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!

    static let demoPassword = "demo1234"

    static func accounts() -> [UserAccount] {
        [
            UserAccount(id: artistUserId, email: "artist@demo.easysesh", role: .artist, status: .active, isVerified: true, settings: UserSettings(), createdAt: .now.adding(days: -120), acceptedTermsVersion: LegalDocument.currentVersion, acceptedTermsAt: .now.adding(days: -120)),
            UserAccount(id: studioOwnerUserId, email: "studio@demo.easysesh", role: .studioOwner, status: .active, isVerified: true, settings: UserSettings(), createdAt: .now.adding(days: -200), acceptedTermsVersion: LegalDocument.currentVersion, acceptedTermsAt: .now.adding(days: -200)),
        ] + otherArtistIds.enumerated().map { index, id in
            UserAccount(id: id, email: "artist\(index + 2)@demo.easysesh", role: .artist, status: .active, isVerified: false, settings: UserSettings(), createdAt: .now.adding(days: -30))
        }
    }

    static func artistProfiles() -> [ArtistProfile] {
        [
            ArtistProfile(
                id: artistUserId,
                artistName: "Nova Lykke",
                genres: [.rnb, .pop, .soul],
                city: "Athens",
                bio: "Danish-Greek singer-songwriter based in Athens. Working on my debut EP.",
                avatarUrl: "https://picsum.photos/seed/nova-avatar/400/400",
                links: [
                    SocialLink(platform: .spotify, url: "https://open.spotify.com/artist/example"),
                    SocialLink(platform: .instagram, url: "https://instagram.com/novalykke"),
                ],
                isVerified: true
            ),
            ArtistProfile(id: otherArtistIds[0], artistName: "Kostas K", genres: [.hipHop, .rap], city: "Athens", bio: "", avatarUrl: nil, links: [], isVerified: false),
            ArtistProfile(id: otherArtistIds[1], artistName: "The Salt Flats", genres: [.indie, .rock], city: "Athens", bio: "", avatarUrl: nil, links: [], isVerified: false),
            ArtistProfile(id: otherArtistIds[2], artistName: "MIRA", genres: [.electronic, .house], city: "Piraeus", bio: "", avatarUrl: nil, links: [], isVerified: true),
        ]
    }

    // MARK: Studios

    private struct Seed {
        var id: UUID
        var owner: UUID
        var name: String
        var tagline: String
        var area: String
        var city: String
        var country: String
        var lat: Double
        var lon: Double
        var rate: Int
        var genres: [Genre]
        var facilities: [Facility]
        var mics: [String]
        var gear: [(EquipmentCategory, String)]
        var rating: Double
        var reviews: Int
        var bookings: Int
        var instant: Bool
        var deposit: Int
        var policy: CancellationPolicy
        var capacity: Int
        var lateNight: Bool
        var currency: String = "EUR"
        var status: StudioStatus = .approved
    }

    static func studios() -> [Studio] {
        let seeds: [Seed] = [
            Seed(id: ownedStudioId, owner: studioOwnerUserId, name: "Exarchia Sound Lab", tagline: "Warm analog vocals in the heart of Exarchia", area: "Exarchia", city: "Athens", country: "Greece", lat: 37.9862, lon: 23.7345, rate: 2500,
                 genres: [.hipHop, .rap, .rnb, .pop], facilities: [.vocalBooth, .controlRoom, .lounge, .wifi, .airConditioning, .publicTransport], mics: ["Neumann U87 Ai", "Shure SM7B", "AKG C414 XLII"],
                 gear: [(.preamp, "Neve 1073 DPX"), (.interface, "Universal Audio Apollo x8"), (.monitors, "Adam A7X"), (.software, "Pro Tools Ultimate"), (.software, "Ableton Live 12")],
                 rating: 4.8, reviews: 64, bookings: 312, instant: false, deposit: 0, policy: .moderate, capacity: 5, lateNight: true),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!, owner: UUID(), name: "Psyri Records", tagline: "Budget-friendly booth for demos and toplines", area: "Psyri", city: "Athens", country: "Greece", lat: 37.9779, lon: 23.7238, rate: 1500,
                 genres: [.hipHop, .rap, .pop, .afro], facilities: [.vocalBooth, .wifi, .airConditioning, .publicTransport], mics: ["Rode NT1", "Shure SM7B"],
                 gear: [(.interface, "Focusrite Scarlett 18i20"), (.monitors, "KRK Rokit 7"), (.software, "FL Studio")],
                 rating: 4.4, reviews: 38, bookings: 520, instant: true, deposit: 0, policy: .flexible, capacity: 3, lateNight: true),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000003")!, owner: UUID(), name: "Koukaki Live Rooms", tagline: "Big live room for bands, rehearsal and tracking", area: "Koukaki", city: "Athens", country: "Greece", lat: 37.9655, lon: 23.7248, rate: 4500,
                 genres: [.rock, .indie, .jazz, .metal, .punk], facilities: [.liveRoom, .controlRoom, .drumRoom, .isolationBooth, .instrumentsAvailable, .lounge, .kitchen, .parking], mics: ["Neumann U47 fet", "Coles 4038", "Shure SM57 (x6)", "Sennheiser MD421 (x4)", "AKG D112"],
                 gear: [(.console, "SSL AWS 948"), (.instrument, "Yamaha C3 grand piano"), (.instrument, "DW Collector's drum kit"), (.outboard, "Universal Audio 1176LN (x2)"), (.monitors, "Barefoot MicroMain27")],
                 rating: 4.9, reviews: 51, bookings: 190, instant: false, deposit: 30, policy: .strict, capacity: 12, lateNight: false),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000004")!, owner: UUID(), name: "Gazi Beat Factory", tagline: "Producer-led sessions, beats and mixdowns", area: "Gazi", city: "Athens", country: "Greece", lat: 37.9785, lon: 23.7105, rate: 3000,
                 genres: [.electronic, .house, .techno, .hipHop], facilities: [.controlRoom, .vocalBooth, .lounge, .wifi, .smokingArea, .publicTransport], mics: ["Neumann TLM 103", "Shure SM7B"],
                 gear: [(.instrument, "Moog Subsequent 37"), (.instrument, "Roland TR-8S"), (.monitors, "Genelec 8340"), (.software, "Ableton Live 12"), (.software, "Logic Pro")],
                 rating: 4.6, reviews: 27, bookings: 140, instant: true, deposit: 50, policy: .moderate, capacity: 6, lateNight: true),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000005")!, owner: UUID(), name: "Kypseli Podcast House", tagline: "Four-mic podcast studio with video", area: "Kypseli", city: "Athens", country: "Greece", lat: 38.0012, lon: 23.7382, rate: 2000,
                 genres: [.podcast, .voiceOver], facilities: [.podcastSetup, .videoRecording, .wifi, .airConditioning, .wheelchairAccess], mics: ["Shure SM7B (x4)", "Electro-Voice RE20"],
                 gear: [(.interface, "RODECaster Pro II"), (.other, "3x Sony FX30 cameras")],
                 rating: 4.7, reviews: 19, bookings: 88, instant: true, deposit: 0, policy: .flexible, capacity: 6, lateNight: false),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000006")!, owner: UUID(), name: "Pangrati Mix Suite", tagline: "Mixing & mastering with a Grammy-nominated engineer", area: "Pangrati", city: "Athens", country: "Greece", lat: 37.9683, lon: 23.7452, rate: 5500,
                 genres: [.pop, .rnb, .soul, .electronic, .greek], facilities: [.controlRoom, .vocalBooth, .lounge, .wifi, .airConditioning], mics: ["Sony C800G", "Neumann U87 Ai", "Telefunken ELA M 251"],
                 gear: [(.console, "API 1608-II"), (.outboard, "Manley Massive Passive"), (.outboard, "Shadow Hills Mastering Compressor"), (.monitors, "PMC IB1S")],
                 rating: 5.0, reviews: 22, bookings: 75, instant: false, deposit: 50, policy: .strict, capacity: 4, lateNight: false),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000007")!, owner: UUID(), name: "Piraeus Harbour Studio", tagline: "Sea-view studio for writing camps", area: "Piraeus", city: "Piraeus", country: "Greece", lat: 37.9420, lon: 23.6465, rate: 3500,
                 genres: [.greek, .pop, .folk, .latin], facilities: [.liveRoom, .controlRoom, .vocalBooth, .kitchen, .parking, .lounge], mics: ["Neumann U87 Ai", "AKG C12 VR"],
                 gear: [(.instrument, "Bouzouki & baglamas"), (.instrument, "Nord Stage 4"), (.monitors, "Focal Trio11")],
                 rating: 4.5, reviews: 14, bookings: 60, instant: true, deposit: 0, policy: .moderate, capacity: 8, lateNight: false),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000008")!, owner: UUID(), name: "Glyfada Vocal Booth", tagline: "Small, bright booth by the coast", area: "Glyfada", city: "Athens", country: "Greece", lat: 37.8655, lon: 23.7530, rate: 1800,
                 genres: [.pop, .rnb, .voiceOver], facilities: [.vocalBooth, .parking, .wifi, .airConditioning], mics: ["Neumann TLM 102", "Aston Spirit"],
                 gear: [(.interface, "Apogee Symphony Desktop"), (.monitors, "Yamaha HS8")],
                 rating: 4.2, reviews: 9, bookings: 40, instant: true, deposit: 0, policy: .flexible, capacity: 3, lateNight: false),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000009")!, owner: UUID(), name: "Nørrebro Tapehouse", tagline: "Tape machines and vintage keys in Copenhagen", area: "Nørrebro", city: "Copenhagen", country: "Denmark", lat: 55.6925, lon: 12.5510, rate: 45000,
                 genres: [.indie, .rock, .folk, .soul], facilities: [.liveRoom, .controlRoom, .instrumentsAvailable, .kitchen, .publicTransport], mics: ["Neumann U67", "RCA 44", "Beyerdynamic M160"],
                 gear: [(.outboard, "Studer A80 tape machine"), (.instrument, "Fender Rhodes Mk I"), (.console, "Neve 5088")],
                 rating: 4.9, reviews: 33, bookings: 150, instant: false, deposit: 30, policy: .moderate, capacity: 10, lateNight: false, currency: "DKK"),
            Seed(id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-00000000000a")!, owner: UUID(), name: "Vesterbro Vocal Club", tagline: "Topline and vocal production", area: "Vesterbro", city: "Copenhagen", country: "Denmark", lat: 55.6685, lon: 12.5505, rate: 30000,
                 genres: [.pop, .rnb, .hipHop], facilities: [.vocalBooth, .controlRoom, .lounge, .wifi], mics: ["Sony C800G", "Neumann U87 Ai"],
                 gear: [(.software, "Logic Pro"), (.monitors, "Neumann KH 310")],
                 rating: 4.6, reviews: 21, bookings: 110, instant: true, deposit: 0, policy: .flexible, capacity: 4, lateNight: true, currency: "DKK"),
        ]
        return seeds.enumerated().map { index, seed in makeStudio(seed, index: index) }
    }

    private static func makeStudio(_ s: Seed, index: Int) -> Studio {
        let slug = s.name.lowercased().replacingOccurrences(of: " ", with: "-")
        var sessionTypes = [
            SessionType(id: "recording", name: "Recording", details: "Studio time for tracking vocals or instruments.", hourlyRate: s.rate, minimumHours: 2, includesEngineer: false),
            SessionType(id: "recording_engineer", name: "Recording + engineer", details: "In-house engineer runs the session.", hourlyRate: s.rate + s.rate / 2, minimumHours: 2, includesEngineer: true),
        ]
        if s.genres.contains(.podcast) {
            sessionTypes = [SessionType(id: "podcast", name: "Podcast session", details: "Mics, cameras and live switching.", hourlyRate: s.rate, minimumHours: 1, includesEngineer: true)]
        }
        if s.facilities.contains(.liveRoom) {
            sessionTypes.append(SessionType(id: "rehearsal", name: "Rehearsal", details: "Live room without recording.", hourlyRate: max(s.rate / 2, 1000), minimumHours: 2, includesEngineer: false))
        }
        let addOns = [
            ServiceAddOn(id: "mixing", kind: .mixing, name: "Mixing", price: s.rate * 3, unit: .perTrack),
            ServiceAddOn(id: "mastering", kind: .mastering, name: "Mastering", price: s.rate, unit: .perTrack),
            ServiceAddOn(id: "producer", kind: .producer, name: "Producer", price: s.rate, unit: .perHour),
        ]
        let mics = s.mics.enumerated().map { EquipmentItem(id: "mic\($0.offset)", category: .microphone, name: $0.element) }
        let gear = s.gear.enumerated().map { EquipmentItem(id: "gear\($0.offset)", category: $0.element.0, name: $0.element.1) }
        let hours = (1...7).map { weekday in
            OpeningHours(weekday: weekday, isClosed: weekday == 1 && !s.lateNight, opensAt: s.lateNight ? 12 * 60 : 9 * 60, closesAt: s.lateNight ? 26 * 60 : 21 * 60)
        }
        return Studio(
            id: s.id,
            ownerId: s.owner,
            name: s.name,
            tagline: s.tagline,
            description: "\(s.name) is a professional recording space in \(s.area). \(s.tagline). Comfortable, acoustically treated rooms, fast Wi-Fi and a team that cares about your sound. Bring your ideas – we'll help you get them down.",
            photoUrls: (1...4).map { "https://picsum.photos/seed/\(slug)-\($0)/1200/800" },
            videoUrl: index == 0 ? "https://www.youtube.com/watch?v=dQw4w9WgXcQ" : nil,
            address: StudioAddress(street: "\(["Themistokleous", "Karaiskaki", "Veikou", "Persefonis", "Fokionos Negri", "Ymittou", "Akti Miaouli", "Lazaraki", "Guldbergsgade", "Istedgade"][index % 10]) \(10 + index * 7)", postalCode: s.country == "Denmark" ? "2200" : "106 81", city: s.city, area: s.area, country: s.country),
            latitude: s.lat,
            longitude: s.lon,
            contact: StudioContact(phone: s.country == "Denmark" ? "+45 12 34 56 78" : "+30 210 123 45\(10 + index)", email: "hello@\(slug).com", website: "https://\(slug).com"),
            currency: s.currency,
            priceFrom: 0,
            sessionTypes: sessionTypes,
            addOns: addOns,
            facilities: s.facilities,
            equipment: mics + gear,
            engineers: [
                StudioPerson(id: "eng1", name: ["Dimitris P.", "Eleni M.", "Nikos A.", "Sofia T."][index % 4], role: "Head engineer", bio: "10+ years recording and mixing."),
                StudioPerson(id: "prod1", name: ["Alex R.", "Maria K.", "Yannis D."][index % 3], role: "Producer", bio: "Beats, arrangement and vocal production."),
            ],
            capacity: s.capacity,
            genres: s.genres,
            openingHours: hours,
            rules: ["No smoking inside", "No food in the control room", "Max \(s.capacity) people", "Please arrive 10 minutes early"],
            bookingPolicy: BookingPolicy(instantBook: s.instant, cancellationPolicy: s.policy, depositPercent: s.deposit, minimumNoticeHours: 6, maxAdvanceDays: 90, bufferMinutes: 0, terms: "Sessions start and end on time. Overtime is billed per started hour."),
            status: s.status,
            isActive: true,
            isVerified: s.rating >= 4.7,
            adminNote: nil,
            ratingAverage: s.rating,
            reviewCount: s.reviews,
            bookingCount: s.bookings,
            createdAt: .now.adding(days: -300 + index * 10),
            submittedAt: .now.adding(days: -290 + index * 10),
            timezone: s.country == "Denmark" ? "Europe/Copenhagen" : "Europe/Athens"
        ).normalized()
    }

    // MARK: Bookings, reviews, chat

    static func bookings(studios: [Studio]) -> [Booking] {
        let owned = studios[0]
        let koukaki = studios[2]
        let calendar = Calendar.current
        func at(daysFromNow: Int, hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date.now.adding(days: daysFromNow)) ?? .now
        }
        func make(_ studio: Studio, artist: UUID, artistName: String, day: Int, hour: Int, hours: Int, status: BookingStatus, payment: PaymentStatus, reviewed: Bool = false) -> Booking {
            let type = studio.sessionTypes[0]
            let price = PricingEngine.quote(studio: studio, sessionType: type, hours: hours)
            let start = at(daysFromNow: day, hour: hour)
            return Booking(
                id: UUID(), reference: BookingReference.make(), artistId: artist, studioId: studio.id,
                artistName: artistName, studioName: studio.name, sessionTypeId: type.id, sessionTypeName: type.name,
                startsAt: start, endsAt: start.adding(hours: hours), hours: hours, addOns: [], status: status,
                paymentStatus: payment, price: price, notes: "", cancellationReason: nil, cancelledBy: nil,
                refundAmount: 0, hasReview: reviewed, createdAt: start.adding(days: -7), updatedAt: start.adding(days: -7)
            )
        }
        return [
            make(owned, artist: artistUserId, artistName: "Nova Lykke", day: 3, hour: 14, hours: 3, status: .confirmed, payment: .paid),
            make(koukaki, artist: artistUserId, artistName: "Nova Lykke", day: -12, hour: 11, hours: 4, status: .completed, payment: .paid),
            make(owned, artist: artistUserId, artistName: "Nova Lykke", day: -40, hour: 16, hours: 2, status: .completed, payment: .paid, reviewed: true),
            make(owned, artist: otherArtistIds[0], artistName: "Kostas K", day: 1, hour: 18, hours: 2, status: .pendingApproval, payment: .authorized),
            make(owned, artist: otherArtistIds[1], artistName: "The Salt Flats", day: 5, hour: 12, hours: 4, status: .confirmed, payment: .paid),
            make(owned, artist: otherArtistIds[2], artistName: "MIRA", day: 8, hour: 20, hours: 3, status: .confirmed, payment: .paid),
            make(owned, artist: otherArtistIds[0], artistName: "Kostas K", day: -3, hour: 15, hours: 2, status: .completed, payment: .paid),
            make(owned, artist: otherArtistIds[2], artistName: "MIRA", day: -9, hour: 19, hours: 5, status: .completed, payment: .paid),
            make(owned, artist: otherArtistIds[1], artistName: "The Salt Flats", day: -20, hour: 13, hours: 3, status: .completed, payment: .paid),
            // Cash bookings: the studio is paid at the session and owes EasySesh 10%.
            cash(make(owned, artist: otherArtistIds[2], artistName: "MIRA", day: -6, hour: 14, hours: 2, status: .confirmed, payment: .payAtStudio)),
            cash(make(owned, artist: otherArtistIds[0], artistName: "Kostas K", day: 2, hour: 20, hours: 3, status: .confirmed, payment: .payAtStudio)),
        ]
    }

    private static func cash(_ booking: Booking) -> Booking {
        var copy = booking
        copy.paymentMethod = .cash
        return copy
    }

    static func reviews(studios: [Studio], bookings: [Booking]) -> [Review] {
        let texts = [
            (5, "Incredible vocal chain and the engineer really knew how to get the best take out of me."),
            (5, "Super clean room, great vibe, on time. Will be back for the EP."),
            (4, "Great sound. Booth is a bit small for two singers, but otherwise perfect."),
            (5, "Best studio experience I've had in Athens."),
            (4, "Good value for money. Coffee could be better."),
        ]
        var reviews: [Review] = []
        for (index, studio) in studios.enumerated() {
            for (offset, entry) in texts.enumerated() where (offset + index) % 2 == 0 || offset < 2 {
                reviews.append(Review(
                    id: UUID(), bookingId: UUID(), studioId: studio.id, artistId: otherArtistIds[offset % 3],
                    artistName: ["Kostas K", "The Salt Flats", "MIRA"][offset % 3],
                    rating: entry.0, facilitiesRating: entry.0, experienceRating: min(5, entry.0 + 1 - offset % 2), engineerRating: offset % 2 == 0 ? 5 : nil,
                    text: entry.1, studioReply: offset == 0 ? "Thank you! It was a pleasure having you here." : nil,
                    studioRepliedAt: offset == 0 ? .now.adding(days: -5) : nil, isHidden: false,
                    createdAt: .now.adding(days: -(offset * 9 + index))
                ))
            }
        }
        if let reviewed = bookings.first(where: { $0.hasReview && $0.artistId == artistUserId }) {
            reviews.append(Review(id: UUID(), bookingId: reviewed.id, studioId: reviewed.studioId, artistId: artistUserId, artistName: "Nova Lykke", rating: 5, facilitiesRating: 5, experienceRating: 5, engineerRating: 5, text: "Dimitris is a wizard. The U87 through the Neve sounds unreal.", studioReply: nil, studioRepliedAt: nil, isHidden: false, createdAt: reviewed.endsAt.adding(days: 1)))
        }
        return reviews
    }
}

enum BookingReference {
    static func make() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "SON-" + String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
