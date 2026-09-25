import SwiftUI

struct ReviewSummaryView: View {
    let studio: Studio
    let reviews: [Review]

    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text(studio.reviewCount == 0 ? "–" : String(format: "%.1f", studio.ratingAverage))
                    .font(.display(44))
                StarRow(rating: Int(studio.ratingAverage.rounded()))
                Text("\(studio.reviewCount) reviews").font(.caption).foregroundStyle(.secondary)
            }
            if !reviews.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    bar("Facilities", average(\.facilitiesRating))
                    bar("Experience", average(\.experienceRating))
                    let engineer = reviews.compactMap(\.engineerRating)
                    if !engineer.isEmpty {
                        bar("Engineer", Double(engineer.reduce(0, +)) / Double(engineer.count))
                    }
                }
            }
        }
        .card()
    }

    private func average(_ keyPath: KeyPath<Review, Int>) -> Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.map { $0[keyPath: keyPath] }.reduce(0, +)) / Double(reviews.count)
    }

    private func bar(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 72, alignment: .leading)
            ProgressView(value: value, total: 5).tint(.primary)
            Text(String(format: "%.1f", value)).font(.caption.monospacedDigit())
        }
    }
}

struct ReviewRow: View {
    @Environment(AppState.self) private var app
    @State var review: Review
    let canReply: Bool

    @State private var showReply = false
    @State private var showReport = false
    @State private var showDispute = false
    @State private var disputed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Avatar(url: nil, name: review.artistName, size: 32)
                VStack(alignment: .leading) {
                    Text(review.artistName).font(.subheadline.bold())
                    Text(review.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StarRow(rating: review.rating)
                Menu {
                    if canReply && review.studioReply == nil {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") { showReply = true }
                    }
                    if canReply && !disputed {
                        Button("Dispute rating", systemImage: "scale.3d") { showDispute = true }
                    }
                    Button("Report review", systemImage: "flag") { showReport = true }
                } label: {
                    Image(systemName: "ellipsis").padding(6)
                }
            }
            Text(review.text).font(.subheadline)
            if let reply = review.studioReply {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Response from the studio").font(.caption.bold())
                    Text(reply).font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
        .sheet(isPresented: $showReport) { ReportSheet(target: .review, targetId: review.id) }
        .sheet(isPresented: $showReply) { ReplySheet(review: $review) }
        .sheet(isPresented: $showDispute) {
            DisputeRatingSheet(kind: .studioReview, reviewId: review.id) { disputed = true }
        }
    }
}

struct ReplySheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var review: Review
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(review.text).foregroundStyle(.secondary)
                }
                Section("Your public reply") {
                    TextField("Thank the artist or respond to feedback", text: $text, axis: .vertical).lineLimit(4...10)
                }
            }
            .easyseshGrouped()
            .navigationTitle("Reply to review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            do {
                                review = try await app.backend.replyToReview(id: review.id, reply: text)
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }
}

struct ReviewsListView: View {
    let studio: Studio
    let reviews: [Review]
    let canReply: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ReviewSummaryView(studio: studio, reviews: reviews)
                ForEach(reviews) { ReviewRow(review: $0, canReply: canReply) }
            }
            .padding()
        }
        .background(Theme.background)
        .easyseshGrouped()
        .navigationTitle("Reviews")
    }
}

struct WriteReviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let booking: Booking
    var onSubmitted: () -> Void = {}

    @State private var rating = 5
    @State private var facilities = 5
    @State private var experience = 5
    @State private var hadEngineer = false
    @State private var engineer = 5
    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text(booking.studioName).font(.headline)
                        Text("\(booking.sessionTypeName) · \(booking.startsAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Ratings") {
                    StarPicker(title: "Overall", rating: $rating)
                    StarPicker(title: "Facilities", rating: $facilities)
                    StarPicker(title: "Studio experience", rating: $experience)
                    Toggle("I worked with an engineer/producer", isOn: $hadEngineer)
                    if hadEngineer { StarPicker(title: "Engineer/producer", rating: $engineer) }
                }
                Section {
                    TextField("What was great? What could be better?", text: $text, axis: .vertical).lineLimit(4...12)
                } header: {
                    Text("Your review")
                } footer: {
                    Text("Reviews are public and shown with your artist name.")
                }
            }
            .easyseshGrouped()
            .navigationTitle("Review your session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }.disabled(isSaving || text.count < 10)
                }
            }
            .errorAlert($error)
        }
        .onAppear { hadEngineer = booking.sessionTypeName.localizedCaseInsensitiveContains("engineer") || booking.addOns.contains { $0.id == "producer" } }
    }

    private func submit() {
        isSaving = true
        let review = Review(
            id: UUID(), bookingId: booking.id, studioId: booking.studioId, artistId: booking.artistId,
            artistName: app.artistProfile?.artistName ?? booking.artistName,
            rating: rating, facilitiesRating: facilities, experienceRating: experience,
            engineerRating: hadEngineer ? engineer : nil, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            studioReply: nil, studioRepliedAt: nil, isHidden: false, createdAt: .now
        )
        Task {
            defer { isSaving = false }
            do {
                _ = try await app.backend.submitReview(review)
                onSubmitted()
                dismiss()
            } catch { self.error = error.userMessage }
        }
    }
}

struct ReportSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    let targetId: UUID

    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var sent = false
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if sent { confirmation } else { form }
            }
            .auroraBackground(height: 320)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? LocalizedStringKey("Done") : LocalizedStringKey("Cancel")) { dismiss() }
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "flag.fill", size: 48, colors: TilePalette.signal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized: target.reportTitle).font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                    Text("Reports are private. The other side isn't told who reported them.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            GlowSectionHeader(title: String(localized: "What's wrong?"))
            VStack(spacing: 8) {
                ForEach(ReportReason.allCases) { option in
                    let isSelected = reason == option
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { reason = option }
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: option.symbol, size: 34, colors: isSelected ? TilePalette.signal : TilePalette.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localized: option.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(localized: option.hint).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                        }
                        .padding(12)
                        .background(Theme.card.opacity(isSelected ? 0.95 : 0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Theme.glassEdge), lineWidth: isSelected ? 1.5 : 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            GlowSectionHeader(title: String(localized: "Details (optional)"))
            TextField("Tell us what happened. Dates, messages and names help us act faster.", text: $details, axis: .vertical)
                .lineLimit(3...8)
                .padding(14)
                .background(Theme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))

            Label("If someone is in danger, contact the local emergency services first.", systemImage: "exclamationmark.shield.fill")
                .font(.caption).foregroundStyle(.secondary)

            Button { send() } label: {
                Text(isSending ? LocalizedStringKey("Sending…") : LocalizedStringKey("Send report"))
            }
            .buttonStyle(.primary)
            .disabled(reason == nil || isSending)
        }
        .padding(20)
    }

    private var confirmation: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.neon).frame(width: 110, height: 110).blur(radius: 20).opacity(0.5)
                IconTile(symbol: "checkmark.shield.fill", size: 84, colors: TilePalette.mint)
            }
            .padding(.top, 40)
            Text("Thanks for letting us know").font(.title2.weight(.heavy))
            Text("Our moderation team will look into it, usually within 24 hours. We may contact you if we need more details.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.primary).padding(.top, 8)
        }
        .padding(24)
    }

    private func send() {
        guard let reason else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await app.backend.report(target: target, targetId: targetId, reason: reason, details: details)
                withAnimation { sent = true }
            } catch { self.error = error.userMessage }
        }
    }
}

/// A studio rates the artist after a completed session. Shown on the artist's profile; the artist
/// can dispute it.
struct RateArtistSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let booking: Booking
    var onSubmitted: () -> Void = {}

    @State private var rating = 5
    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "star.bubble.fill", size: 44, colors: TilePalette.violet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rate \(booking.artistName)").font(.title3.weight(.heavy))
                            Text("\(booking.sessionTypeName) · \(booking.startsAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    StarPicker(title: "Overall", rating: $rating)
                        .glassCard(padding: 14)
                    TextField("How was the session? Punctual, respectful, prepared?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(14)
                        .background(Theme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    Text("Ratings are shown on the artist's profile with your studio name. Be fair: the artist can ask EasySesh to review it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { submit() } label: {
                        Text(isSaving ? LocalizedStringKey("Sending…") : LocalizedStringKey("Submit rating"))
                    }
                    .buttonStyle(.primary)
                    .disabled(isSaving)
                }
                .padding(20)
            }
            .auroraBackground(height: 300)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } } }
            .errorAlert($error)
        }
        .presentationDetents([.large])
    }

    private func submit() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await app.backend.reviewArtist(bookingId: booking.id, rating: rating, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                onSubmitted()
                dismiss()
            } catch { self.error = error.userMessage }
        }
    }
}
