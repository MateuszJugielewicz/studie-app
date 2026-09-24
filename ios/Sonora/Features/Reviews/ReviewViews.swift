import SwiftUI

struct ReviewSummaryView: View {
    let studio: Studio
    let reviews: [Review]

    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text(studio.reviewCount == 0 ? "–" : String(format: "%.1f", studio.ratingAverage))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
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
            ProgressView(value: value, total: 5).tint(.yellow)
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

    @State private var reason: ReportReason = .fake
    @State private var details = ""
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    ContentUnavailableView("Thanks for letting us know", systemImage: "checkmark.shield", description: Text("Our moderation team will look into it."))
                } else {
                    Section("Why are you reporting this \(target.rawValue)?") {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section("Details (optional)") {
                        TextField("Tell us more", text: $details, axis: .vertical).lineLimit(3...8)
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task {
                                do {
                                    try await app.backend.report(target: target, targetId: targetId, reason: reason, details: details)
                                    sent = true
                                } catch { self.error = error.userMessage }
                            }
                        }
                    }
                }
            }
            .errorAlert($error)
        }
    }
}
