import SwiftUI

/// Renders a bundled Markdown legal document (headings, bullets, paragraphs with inline formatting).
struct LegalDocumentView: View {
    @Environment(AppPreferences.self) private var preferences
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let level, let text):
                        Text(inline(text))
                            .font(level == 1 ? .title.bold() : level == 2 ? .title3.bold() : .headline)
                            .padding(.top, level == 1 ? 0 : 8)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(inline(text))
                        }
                    case .paragraph(let text):
                        Text(inline(text))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Theme.background)
        .easyseshGrouped()
        .navigationTitle(Text(localized: document.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in document.markdown(language: preferences.language.rawValue).components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<!--") {
                flush()
            } else if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#") {
                flush()
                result.append(.heading(line.distance(from: line.startIndex, to: hashes), String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                result.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct LegalListView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            Section {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink {
                        LegalDocumentView(document: document)
                    } label: {
                        Label { Text(localized: document.title) } icon: { Image(systemName: document.symbol) }
                    }
                }
            } footer: {
                Text("Version \(app.requiredTermsVersion). Questions? \(AppConfig.supportEmail)")
            }
        }
        .easyseshGrouped()
        .navigationTitle("Legal")
    }
}

/// Shown when the signed-in user hasn't accepted the current terms (new account via Apple/Google,
/// or after the EasySesh team published a legal update). Every document has to be opened before
/// the user can accept.
struct TermsAcceptanceView: View {
    @Environment(AppState.self) private var app
    @State private var opened: Set<LegalDocument> = []
    @State private var agreed = false
    @State private var isSaving = false
    @State private var error: String?

    private var documents: [LegalDocument] { LegalDocument.required(for: app.role) }
    private var isUpdate: Bool { app.account?.acceptedTermsVersion != nil }
    private var allRead: Bool { documents.allSatisfy(opened.contains) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        EasySeshLogo(size: 22)
                        Text(isUpdate ? LocalizedStringKey("We've updated our terms") : LocalizedStringKey("Before you start"))
                            .font(.system(size: 30, weight: .heavy)).tracking(-0.6)
                        Text(isUpdate
                             ? LocalizedStringKey("Please read the updated documents again and accept them to keep using EasySesh.")
                             : LocalizedStringKey("Please read and accept the documents below to use EasySesh."))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    if let update = app.pendingLegalUpdate {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("What changed", systemImage: "sparkles").font(.caption.weight(.heavy)).textCase(.uppercase).foregroundStyle(Theme.accent)
                            Text(localized: update.title).font(.headline)
                            if !update.body.isEmpty { Text(update.body).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .glassCard()
                    }

                    VStack(spacing: 0) {
                        ForEach(documents) { document in
                            NavigationLink {
                                LegalDocumentView(document: document)
                                    .onAppear { opened.insert(document) }
                            } label: {
                                HStack(spacing: 12) {
                                    IconTile(symbol: document.symbol, size: 36, colors: opened.contains(document) ? TilePalette.mint : TilePalette.violet)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(localized: document.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(opened.contains(document) ? LocalizedStringKey("Read") : LocalizedStringKey("Tap to read"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: opened.contains(document) ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(opened.contains(document) ? Theme.positive : Color.secondary)
                                }
                                .padding(.vertical, 10)
                            }
                            if document != documents.last { Divider().opacity(0.4) }
                        }
                    }
                    .glassCard(padding: 12)

                    Toggle(isOn: $agreed) {
                        Text("I have read and accept these documents").font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.accent)
                    .disabled(!allRead)
                    .glassCard(padding: 14)

                    if !allRead {
                        Label("Open each document to continue.", systemImage: "hand.point.up.left.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Button {
                        accept()
                    } label: {
                        Text(isSaving ? LocalizedStringKey("Saving…") : LocalizedStringKey("Accept and continue"))
                    }
                    .buttonStyle(.primary)
                    .disabled(!agreed || !allRead || isSaving)

                    Text("We record the version and time of your acceptance. You can withdraw consent by deleting your account in Settings.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .auroraBackground(height: 360)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await app.signOut() } }
                }
            }
            .errorAlert($error)
        }
    }

    private func accept() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do { app.updateAccount(try await app.backend.acceptTerms(version: app.requiredTermsVersion)) }
            catch { self.error = error.userMessage }
        }
    }
}

/// A warning from the EasySesh team. It stays until the user confirms they've read it.
struct WarningSheet: View {
    @Environment(AppState.self) private var app
    let warning: ModerationWarning
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "exclamationmark.triangle.fill", size: 48, colors: TilePalette.signal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Warning from EasySesh").font(.title3.weight(.heavy))
                        Text(warning.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(warning.reason)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                Text("Please follow our Community Guidelines. Further breaches can lead to your account being suspended or banned.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink { LegalDocumentView(document: .communityGuidelines) } label: {
                    Label("Read the Community Guidelines", systemImage: "person.3.fill").font(.subheadline.weight(.semibold))
                }
                Button {
                    isSaving = true
                    Task { await app.acknowledgeWarning(warning); isSaving = false }
                } label: {
                    Text("I understand")
                }
                .buttonStyle(.primary)
                .disabled(isSaving)
            }
            .padding(20)
        }
        .auroraBackground(height: 300)
        .interactiveDismissDisabled()
    }
}

/// "What's new": update notes from the EasySesh team, shown once after they're published.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ChangelogEntry]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "sparkles", size: 44, colors: TilePalette.violet)
                        Text("What's new").font(.system(size: 30, weight: .heavy)).tracking(-0.6)
                    }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.version).font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                                Spacer()
                                Text(entry.publishedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(localized: entry.title).font(.headline)
                            if !entry.body.isEmpty {
                                Text(entry.body).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .glassCard()
                    }
                    Button("Got it") { dismiss() }.buttonStyle(.primary)
                }
                .padding(20)
            }
            .auroraBackground(height: 300)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// All update notes, for Settings.
struct ChangelogView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if app.changelog.isEmpty {
                    GlassEmptyState(title: "No updates yet", symbol: "sparkles", message: "Update notes from the EasySesh team show up here.")
                }
                ForEach(app.changelog) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.version).font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                            if entry.isLegalUpdate {
                                Text("Legal update").font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.violet.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Theme.violet)
                            }
                            Spacer()
                            Text(entry.publishedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(localized: entry.title).font(.headline)
                        if !entry.body.isEmpty { Text(entry.body).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .glassCard()
                }
            }
            .padding()
        }
        .auroraBackground(height: 300)
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await Task { await app.refreshUpdates() }.value }
    }
}

/// GDPR: lets the user download everything EasySesh stores about them. One tap builds the file
/// and opens the share sheet (save to Files, AirDrop, mail…).
struct DataExportButton: View {
    @Environment(AppState.self) private var app
    @State private var fileURL: URL?
    @State private var isSharing = false
    @State private var isExporting = false
    @State private var error: String?

    var body: some View {
        Button {
            if fileURL != nil { isSharing = true } else { export() }
        } label: {
            HStack {
                SettingsIcon(symbol: fileURL == nil ? "arrow.down.doc.fill" : "square.and.arrow.up.fill",
                             colors: fileURL == nil ? TilePalette.ocean : TilePalette.mint)
                Text(isExporting ? LocalizedStringKey("Preparing…")
                     : fileURL == nil ? LocalizedStringKey("Download my data") : LocalizedStringKey("Share my data file"))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isExporting { ProgressView() }
            }
        }
        .disabled(isExporting)
        .sheet(isPresented: $isSharing) {
            if let fileURL { ShareSheet(items: [fileURL]).presentationDetents([.medium, .large]) }
        }
        .errorAlert($error)
    }

    private func export() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await app.backend.exportPersonalData()
                let name = "easysesh-data-\(Date.now.formatted(.iso8601.year().month().day())).json"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                fileURL = url
                isSharing = true
            } catch { self.error = error.userMessage }
        }
    }
}

/// The system share sheet (Save to Files, AirDrop, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
