import Foundation

// Raw values are snake_case so they map 1:1 to the Postgres enums in supabase/migrations.

enum UserRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case artist
    case studioOwner = "studio_owner"
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artist: "Artist"
        case .studioOwner: "Studio"
        case .admin: "Admin"
        }
    }
}

enum AccountStatus: String, Codable, CaseIterable, Hashable {
    case active, suspended, banned
}

enum Genre: String, Codable, CaseIterable, Identifiable, Hashable {
    case hipHop = "hip_hop"
    case rap
    case rnb
    case pop
    case rock
    case indie
    case electronic
    case house
    case techno
    case jazz
    case soul
    case classical
    case metal
    case punk
    case folk
    case afro
    case latin
    case reggae
    case greek
    case podcast
    case voiceOver = "voice_over"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hipHop: "Hip-hop"
        case .rap: "Rap"
        case .rnb: "R&B"
        case .pop: "Pop"
        case .rock: "Rock"
        case .indie: "Indie"
        case .electronic: "Electronic"
        case .house: "House"
        case .techno: "Techno"
        case .jazz: "Jazz"
        case .soul: "Soul"
        case .classical: "Classical"
        case .metal: "Metal"
        case .punk: "Punk"
        case .folk: "Folk"
        case .afro: "Afro"
        case .latin: "Latin"
        case .reggae: "Reggae"
        case .greek: "Greek / Laïká"
        case .podcast: "Podcast"
        case .voiceOver: "Voice-over"
        case .other: "Other"
        }
    }
}

enum Facility: String, Codable, CaseIterable, Identifiable, Hashable {
    case vocalBooth = "vocal_booth"
    case liveRoom = "live_room"
    case controlRoom = "control_room"
    case isolationBooth = "isolation_booth"
    case drumRoom = "drum_room"
    case lounge
    case kitchen
    case wifi
    case airConditioning = "air_conditioning"
    case parking
    case publicTransport = "public_transport"
    case wheelchairAccess = "wheelchair_access"
    case smokingArea = "smoking_area"
    case podcastSetup = "podcast_setup"
    case videoRecording = "video_recording"
    case instrumentsAvailable = "instruments_available"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocalBooth: "Vocal booth"
        case .liveRoom: "Live room"
        case .controlRoom: "Control room"
        case .isolationBooth: "Isolation booth"
        case .drumRoom: "Drum room"
        case .lounge: "Lounge"
        case .kitchen: "Kitchen"
        case .wifi: "Wi-Fi"
        case .airConditioning: "Air conditioning"
        case .parking: "Parking"
        case .publicTransport: "Near public transport"
        case .wheelchairAccess: "Wheelchair access"
        case .smokingArea: "Smoking area"
        case .podcastSetup: "Podcast setup"
        case .videoRecording: "Video recording"
        case .instrumentsAvailable: "Instruments available"
        }
    }

    var symbol: String {
        switch self {
        case .vocalBooth: "music.mic"
        case .liveRoom: "music.note.house"
        case .controlRoom: "slider.horizontal.3"
        case .isolationBooth: "square.dashed"
        case .drumRoom: "circle.circle"
        case .lounge: "sofa"
        case .kitchen: "cup.and.saucer"
        case .wifi: "wifi"
        case .airConditioning: "snowflake"
        case .parking: "car"
        case .publicTransport: "tram"
        case .wheelchairAccess: "figure.roll"
        case .smokingArea: "smoke"
        case .podcastSetup: "mic.and.signal.meter"
        case .videoRecording: "video"
        case .instrumentsAvailable: "pianokeys"
        }
    }
}

enum EquipmentCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case microphone
    case preamp
    case console
    case monitors
    case interface
    case outboard
    case instrument
    case software
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphones"
        case .preamp: "Preamps"
        case .console: "Consoles"
        case .monitors: "Monitors"
        case .interface: "Interfaces"
        case .outboard: "Outboard gear"
        case .instrument: "Instruments"
        case .software: "Software"
        case .other: "Other"
        }
    }
}

enum StudioStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case pendingReview = "pending_review"
    case changesRequested = "changes_requested"
    case approved
    case rejected
    case suspended

    var title: String {
        switch self {
        case .draft: "Draft"
        case .pendingReview: "Pending review"
        case .changesRequested: "Changes requested"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .suspended: "Suspended"
        }
    }
}

enum CancellationPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case flexible
    case moderate
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flexible: "Flexible"
        case .moderate: "Moderate"
        case .strict: "Strict"
        }
    }

    var summary: String {
        switch self {
        case .flexible: "Full refund up to 24 hours before the session."
        case .moderate: "Full refund up to 72 hours before, 50% up to 24 hours before."
        case .strict: "50% refund up to 7 days before the session. No refund after that."
        }
    }
}

enum BookingStatus: String, Codable, CaseIterable, Hashable {
    case awaitingPayment = "awaiting_payment"
    case pendingApproval = "pending_approval"
    case confirmed
    case declined
    case cancelled
    case completed
    case disputed
    case expired

    var title: String {
        switch self {
        case .awaitingPayment: "Awaiting payment"
        case .pendingApproval: "Awaiting studio"
        case .confirmed: "Confirmed"
        case .declined: "Declined"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        case .disputed: "In dispute"
        case .expired: "Expired"
        }
    }

    var isActive: Bool { [.pendingApproval, .confirmed].contains(self) }
    var isClosed: Bool { [.declined, .cancelled, .completed, .expired].contains(self) }
}

enum PaymentStatus: String, Codable, CaseIterable, Hashable {
    case unpaid
    case authorized
    case depositPaid = "deposit_paid"
    case paid
    case partiallyRefunded = "partially_refunded"
    case refunded
    case failed
    case payAtStudio = "pay_at_studio"

    var title: String {
        switch self {
        case .payAtStudio: "Pay cash at studio"
        case .unpaid: "Unpaid"
        case .authorized: "Card authorised"
        case .depositPaid: "Deposit paid"
        case .paid: "Paid"
        case .partiallyRefunded: "Partially refunded"
        case .refunded: "Refunded"
        case .failed: "Payment failed"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case card
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case cash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Cash at the studio"
        case .card: "Card"
        case .applePay: "Apple Pay"
        case .googlePay: "Google Pay"
        }
    }
}

enum TransactionKind: String, Codable, Hashable {
    case charge
    case balance
    case refund
}

enum TransactionStatus: String, Codable, Hashable {
    case pending
    case succeeded
    case failed
}

enum PayoutStatus: String, Codable, CaseIterable, Hashable {
    case scheduled
    case inTransit = "in_transit"
    case paid
    case failed

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .inTransit: "On the way"
        case .paid: "Paid"
        case .failed: "Failed"
        }
    }
}

enum MessageKind: String, Codable, Hashable {
    case text
    case system
    case booking
}

enum NotificationKind: String, Codable, CaseIterable, Hashable {
    // Artist
    case bookingConfirmed = "booking_confirmed"
    case bookingChanged = "booking_changed"
    case bookingCancelled = "booking_cancelled"
    case bookingDeclined = "booking_declined"
    case sessionReminder = "session_reminder"
    case refundIssued = "refund_issued"
    case reviewReminder = "review_reminder"
    // Studio
    case bookingRequested = "booking_requested"
    case newReview = "new_review"
    case payoutSent = "payout_sent"
    case studioApproved = "studio_approved"
    case studioRejected = "studio_rejected"
    case studioChangesRequested = "studio_changes_requested"
    // Both
    case newMessage = "new_message"
    case system

    var symbol: String {
        switch self {
        case .bookingConfirmed: "checkmark.seal.fill"
        case .bookingChanged: "calendar.badge.clock"
        case .bookingCancelled, .bookingDeclined: "xmark.circle.fill"
        case .sessionReminder: "alarm.fill"
        case .refundIssued: "arrow.uturn.backward.circle.fill"
        case .reviewReminder, .newReview: "star.fill"
        case .bookingRequested: "calendar.badge.plus"
        case .payoutSent: "banknote.fill"
        case .studioApproved: "checkmark.shield.fill"
        case .studioRejected: "xmark.shield.fill"
        case .studioChangesRequested: "pencil.circle.fill"
        case .newMessage: "bubble.left.fill"
        case .system: "info.circle.fill"
        }
    }
}

enum ReportTarget: String, Codable, CaseIterable, Hashable {
    case user, studio, review, message, booking
}

enum ReportReason: String, Codable, CaseIterable, Identifiable, Hashable {
    case fake
    case spam
    case abusive
    case inappropriate
    case fraud
    case noShow = "no_show"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fake: "Fake or misleading"
        case .spam: "Spam"
        case .abusive: "Abusive or harassing"
        case .inappropriate: "Inappropriate content"
        case .fraud: "Fraud or scam"
        case .noShow: "No-show"
        case .other: "Something else"
        }
    }
}

enum ReportStatus: String, Codable, Hashable {
    case open, resolved, dismissed
}

enum SocialPlatform: String, Codable, CaseIterable, Identifiable, Hashable {
    case spotify
    case appleMusic = "apple_music"
    case instagram
    case tiktok
    case youtube
    case soundcloud
    case website

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .soundcloud: "SoundCloud"
        case .website: "Website"
        }
    }

    var symbol: String {
        switch self {
        case .spotify, .appleMusic, .soundcloud: "music.note"
        case .instagram: "camera"
        case .tiktok: "play.rectangle"
        case .youtube: "play.tv"
        case .website: "globe"
        }
    }
}
