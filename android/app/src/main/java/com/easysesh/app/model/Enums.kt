package com.easysesh.app.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Serial names are snake_case so they map 1:1 to the Postgres enums in supabase/migrations.
// `title` values are English keys; the UI translates them with tr().

@Serializable
enum class UserRole(val raw: String, val title: String) {
    @SerialName("artist") Artist("artist", "Artist"),
    @SerialName("studio_owner") StudioOwner("studio_owner", "Studio"),
    @SerialName("admin") Admin("admin", "Admin"),
}

@Serializable
enum class AccountStatus { @SerialName("active") Active, @SerialName("suspended") Suspended, @SerialName("banned") Banned }

@Serializable
enum class Genre(val raw: String, val title: String) {
    @SerialName("hip_hop") HipHop("hip_hop", "Hip-hop"),
    @SerialName("rap") Rap("rap", "Rap"),
    @SerialName("rnb") Rnb("rnb", "R&B"),
    @SerialName("pop") Pop("pop", "Pop"),
    @SerialName("rock") Rock("rock", "Rock"),
    @SerialName("indie") Indie("indie", "Indie"),
    @SerialName("electronic") Electronic("electronic", "Electronic"),
    @SerialName("house") House("house", "House"),
    @SerialName("techno") Techno("techno", "Techno"),
    @SerialName("jazz") Jazz("jazz", "Jazz"),
    @SerialName("soul") Soul("soul", "Soul"),
    @SerialName("classical") Classical("classical", "Classical"),
    @SerialName("metal") Metal("metal", "Metal"),
    @SerialName("punk") Punk("punk", "Punk"),
    @SerialName("folk") Folk("folk", "Folk"),
    @SerialName("afro") Afro("afro", "Afro"),
    @SerialName("latin") Latin("latin", "Latin"),
    @SerialName("reggae") Reggae("reggae", "Reggae"),
    @SerialName("greek") Greek("greek", "Greek / Laïká"),
    @SerialName("podcast") Podcast("podcast", "Podcast"),
    @SerialName("voice_over") VoiceOver("voice_over", "Voice-over"),
    @SerialName("other") Other("other", "Other");

    companion object { fun from(raw: String) = entries.firstOrNull { it.raw == raw } }
}

@Serializable
enum class Facility(val raw: String, val title: String, val symbol: String) {
    @SerialName("vocal_booth") VocalBooth("vocal_booth", "Vocal booth", "music.mic"),
    @SerialName("live_room") LiveRoom("live_room", "Live room", "music.note.house"),
    @SerialName("control_room") ControlRoom("control_room", "Control room", "slider.horizontal.3"),
    @SerialName("isolation_booth") IsolationBooth("isolation_booth", "Isolation booth", "square.dashed"),
    @SerialName("drum_room") DrumRoom("drum_room", "Drum room", "circle.circle"),
    @SerialName("lounge") Lounge("lounge", "Lounge", "sofa"),
    @SerialName("kitchen") Kitchen("kitchen", "Kitchen", "cup.and.saucer"),
    @SerialName("wifi") Wifi("wifi", "Wi-Fi", "wifi"),
    @SerialName("air_conditioning") AirConditioning("air_conditioning", "Air conditioning", "snowflake"),
    @SerialName("parking") Parking("parking", "Parking", "car"),
    @SerialName("public_transport") PublicTransport("public_transport", "Near public transport", "tram"),
    @SerialName("wheelchair_access") WheelchairAccess("wheelchair_access", "Wheelchair access", "figure.roll"),
    @SerialName("smoking_area") SmokingArea("smoking_area", "Smoking area", "smoke"),
    @SerialName("podcast_setup") PodcastSetup("podcast_setup", "Podcast setup", "mic.and.signal.meter"),
    @SerialName("video_recording") VideoRecording("video_recording", "Video recording", "video"),
    @SerialName("instruments_available") InstrumentsAvailable("instruments_available", "Instruments available", "pianokeys"),
}

@Serializable
enum class EquipmentCategory(val raw: String, val title: String) {
    @SerialName("microphone") Microphone("microphone", "Microphones"),
    @SerialName("preamp") Preamp("preamp", "Preamps"),
    @SerialName("console") Console("console", "Consoles"),
    @SerialName("monitors") Monitors("monitors", "Monitors"),
    @SerialName("interface") Interface("interface", "Interfaces"),
    @SerialName("outboard") Outboard("outboard", "Outboard gear"),
    @SerialName("instrument") Instrument("instrument", "Instruments"),
    @SerialName("software") Software("software", "Software"),
    @SerialName("other") Other("other", "Other"),
}

@Serializable
enum class StudioStatus(val raw: String, val title: String) {
    @SerialName("draft") Draft("draft", "Draft"),
    @SerialName("pending_review") PendingReview("pending_review", "Pending review"),
    @SerialName("changes_requested") ChangesRequested("changes_requested", "Changes requested"),
    @SerialName("approved") Approved("approved", "Approved"),
    @SerialName("rejected") Rejected("rejected", "Rejected"),
    @SerialName("suspended") Suspended("suspended", "Suspended"),
}

@Serializable
enum class CancellationPolicy(val raw: String, val title: String, val summary: String) {
    @SerialName("flexible") Flexible("flexible", "Flexible", "Full refund up to 24 hours before the session."),
    @SerialName("moderate") Moderate("moderate", "Moderate", "Full refund up to 72 hours before, 50% up to 24 hours before."),
    @SerialName("strict") Strict("strict", "Strict", "50% refund up to 7 days before the session. No refund after that."),
}

@Serializable
enum class BookingStatus(val raw: String, val title: String) {
    @SerialName("awaiting_payment") AwaitingPayment("awaiting_payment", "Awaiting payment"),
    @SerialName("pending_approval") PendingApproval("pending_approval", "Awaiting studio"),
    @SerialName("confirmed") Confirmed("confirmed", "Confirmed"),
    @SerialName("declined") Declined("declined", "Declined"),
    @SerialName("cancelled") Cancelled("cancelled", "Cancelled"),
    @SerialName("completed") Completed("completed", "Completed"),
    @SerialName("disputed") Disputed("disputed", "In dispute"),
    @SerialName("expired") Expired("expired", "Expired");

    val isActive get() = this == PendingApproval || this == Confirmed
    val isClosed get() = this in listOf(Declined, Cancelled, Completed, Expired)
}

@Serializable
enum class PaymentStatus(val raw: String, val title: String) {
    @SerialName("unpaid") Unpaid("unpaid", "Unpaid"),
    @SerialName("authorized") Authorized("authorized", "Card authorised"),
    @SerialName("deposit_paid") DepositPaid("deposit_paid", "Deposit paid"),
    @SerialName("paid") Paid("paid", "Paid"),
    @SerialName("partially_refunded") PartiallyRefunded("partially_refunded", "Partially refunded"),
    @SerialName("refunded") Refunded("refunded", "Refunded"),
    @SerialName("failed") Failed("failed", "Payment failed"),
    @SerialName("pay_at_studio") PayAtStudio("pay_at_studio", "Pay cash at studio"),
}

@Serializable
enum class PaymentMethod(val raw: String, val title: String) {
    @SerialName("card") Card("card", "Card"),
    @SerialName("apple_pay") ApplePay("apple_pay", "Apple Pay"),
    @SerialName("google_pay") GooglePay("google_pay", "Google Pay"),
    @SerialName("cash") Cash("cash", "Cash at the studio"),
}

@Serializable
enum class TransactionKind { @SerialName("charge") Charge, @SerialName("balance") Balance, @SerialName("refund") Refund }

@Serializable
enum class TransactionStatus { @SerialName("pending") Pending, @SerialName("succeeded") Succeeded, @SerialName("failed") Failed }

@Serializable
enum class PayoutStatus(val raw: String, val title: String) {
    @SerialName("scheduled") Scheduled("scheduled", "Scheduled"),
    @SerialName("in_transit") InTransit("in_transit", "On the way"),
    @SerialName("paid") Paid("paid", "Paid"),
    @SerialName("failed") Failed("failed", "Failed"),
}

@Serializable
enum class MessageKind { @SerialName("text") Text, @SerialName("system") System, @SerialName("booking") Booking }

@Serializable
enum class NotificationKind(val raw: String, val symbol: String) {
    // Artist
    @SerialName("booking_confirmed") BookingConfirmed("booking_confirmed", "checkmark.seal.fill"),
    @SerialName("booking_changed") BookingChanged("booking_changed", "calendar.badge.clock"),
    @SerialName("booking_cancelled") BookingCancelled("booking_cancelled", "xmark.circle.fill"),
    @SerialName("booking_declined") BookingDeclined("booking_declined", "xmark.circle.fill"),
    @SerialName("session_reminder") SessionReminder("session_reminder", "alarm.fill"),
    @SerialName("refund_issued") RefundIssued("refund_issued", "arrow.uturn.backward.circle.fill"),
    @SerialName("review_reminder") ReviewReminder("review_reminder", "star.fill"),
    // Studio
    @SerialName("booking_requested") BookingRequested("booking_requested", "calendar.badge.plus"),
    @SerialName("new_review") NewReview("new_review", "star.fill"),
    @SerialName("payout_sent") PayoutSent("payout_sent", "banknote.fill"),
    @SerialName("studio_approved") StudioApproved("studio_approved", "checkmark.shield.fill"),
    @SerialName("studio_rejected") StudioRejected("studio_rejected", "xmark.shield.fill"),
    @SerialName("studio_changes_requested") StudioChangesRequested("studio_changes_requested", "pencil.circle.fill"),
    // Both
    @SerialName("new_message") NewMessage("new_message", "bubble.left.fill"),
    @SerialName("system") System("system", "info.circle.fill"),
}

@Serializable
enum class ReportTarget(val raw: String, val reportTitle: String) {
    @SerialName("user") User("user", "Report user"),
    @SerialName("studio") Studio("studio", "Report studio"),
    @SerialName("review") Review("review", "Report review"),
    @SerialName("message") Message("message", "Report message"),
    @SerialName("booking") Booking("booking", "Report booking"),
}

@Serializable
enum class ReportReason(val raw: String, val title: String, val hint: String, val symbol: String) {
    @SerialName("fake") Fake("fake", "Fake or misleading", "Fake profile, photos or information", "person.crop.circle.badge.questionmark"),
    @SerialName("spam") Spam("spam", "Spam", "Advertising, repeated or unwanted messages", "envelope.badge"),
    @SerialName("abusive") Abusive("abusive", "Abusive or harassing", "Insults, threats or harassment", "hand.raised.fill"),
    @SerialName("inappropriate") Inappropriate("inappropriate", "Inappropriate content", "Offensive, sexual or violent content", "eye.slash.fill"),
    @SerialName("fraud") Fraud("fraud", "Fraud or scam", "Asking to pay outside EasySesh, scams or stolen cards", "creditcard.trianglebadge.exclamationmark"),
    @SerialName("no_show") NoShow("no_show", "No-show", "Didn't turn up or the studio was closed", "calendar.badge.exclamationmark"),
    @SerialName("other") Other("other", "Something else", "Anything else that breaks our rules", "ellipsis.bubble.fill"),
}

@Serializable
enum class ReportStatus { @SerialName("open") Open, @SerialName("resolved") Resolved, @SerialName("dismissed") Dismissed }

@Serializable
enum class SocialPlatform(val raw: String, val title: String, val symbol: String) {
    @SerialName("spotify") Spotify("spotify", "Spotify", "music.note"),
    @SerialName("apple_music") AppleMusic("apple_music", "Apple Music", "music.note"),
    @SerialName("instagram") Instagram("instagram", "Instagram", "camera"),
    @SerialName("tiktok") Tiktok("tiktok", "TikTok", "play.rectangle"),
    @SerialName("youtube") Youtube("youtube", "YouTube", "play.tv"),
    @SerialName("soundcloud") Soundcloud("soundcloud", "SoundCloud", "music.note"),
    @SerialName("website") Website("website", "Website", "globe"),
}
