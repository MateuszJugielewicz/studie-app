import SwiftUI

struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed, transaction: Transaction(animation: .easeIn)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                default:
                    placeholder.overlay(ProgressView())
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.fill
            Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
        }
    }
}

struct Avatar: View {
    let url: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if url != nil {
                RemoteImage(url: url)
            } else {
                Theme.fill
                Text(initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct RatingLabel: View {
    let rating: Double
    let count: Int
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(.primary)
            if count == 0 {
                Text("New").fontWeight(.semibold)
            } else {
                Text(rating, format: .number.precision(.fractionLength(1))).fontWeight(.semibold)
                if !compact { Text("(\(count))").foregroundStyle(.secondary) }
            }
        }
        .font(.subheadline)
    }
}

struct StarRow: View {
    let rating: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index <= rating ? Color.primary : Color.secondary.opacity(0.5))
            }
        }
    }
}

struct StarPicker: View {
    let title: String
    @Binding var rating: Int

    var body: some View {
        HStack {
            Text(localized: title)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(index <= rating ? Theme.accent : Color.secondary.opacity(0.5))
                        .onTapGesture { rating = index }
                        .accessibilityLabel("\(index) stars")
                }
            }
        }
    }
}

struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.subheadline)
            .foregroundStyle(.blue)
            .accessibilityLabel("Verified")
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(localized: text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
            .foregroundStyle(color)
    }
}

extension BookingStatus {
    var color: Color {
        switch self {
        case .awaitingPayment, .pendingApproval: Theme.warning
        case .confirmed: Theme.positive
        case .completed: .secondary
        case .declined, .cancelled, .expired: .gray
        case .disputed: .red
        }
    }
}

extension StudioStatus {
    var color: Color {
        switch self {
        case .draft: .gray
        case .pendingReview: Theme.warning
        case .changesRequested: Theme.warning
        case .approved: Theme.positive
        case .rejected, .suspended: .red
        }
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let title: String
    var symbol: String?
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(localized: title)
        }
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                Capsule().fill(Theme.neon).neonGlow(Theme.magenta, radius: 8)
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .overlay(Capsule().strokeBorder(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.12)))
        .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

/// Multi-select chip picker for any CaseIterable enum.
struct ChipPicker<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Set<Item>
    let title: (Item) -> String
    var symbol: ((Item) -> String)?

    var body: some View {
        FlowLayout {
            ForEach(items) { item in
                Button {
                    if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    Chip(title: title(item), symbol: symbol?(item), isSelected: selection.contains(item))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(localized: title).font(.title3.weight(.bold))
            Spacer()
            if let action {
                Button(action.title, action: action.run).font(.subheadline)
            }
        }
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
            Text(localized: title)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
    }
}

struct PriceRow: View {
    let title: String
    let amount: Int
    let currency: String
    var emphasized = false

    var body: some View {
        HStack {
            Text(localized: title)
            Spacer()
            Text(Money.format(amount, currency: currency))
        }
        .font(emphasized ? .headline : .body)
        .foregroundStyle(emphasized ? Color.primary : Color.secondary)
    }
}

/// Presents `error` as an alert and clears it on dismiss.
struct ErrorAlert: ViewModifier {
    @Binding var error: String?

    func body(content: Content) -> some View {
        // Empty messages come from cancelled requests (pull-to-refresh, typing while searching): not shown.
        content.alert("Something went wrong", isPresented: Binding(get: { !(error ?? "").isEmpty }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}

extension View {
    func errorAlert(_ error: Binding<String?>) -> some View { modifier(ErrorAlert(error: error)) }
}

extension Error {
    /// The request was cancelled (view went away, refresh restarted, new search typed). Not a real failure.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        return (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == NSURLErrorCancelled
    }

    /// Message for the user; empty for cancellations, which the error alert ignores.
    var userMessage: String {
        if isCancellation { return "" }
        // Messages from the app and the server are English keys; show them in the chosen language.
        return L10n.tr((self as? LocalizedError)?.errorDescription ?? localizedDescription)
    }
}

extension Text {
    /// Looks the string up in the translations (falls back to the string itself), for components
    /// that take titles as `String`, such as enum titles and section headers.
    init(localized string: String) {
        self.init(LocalizedStringKey(string))
    }
}
