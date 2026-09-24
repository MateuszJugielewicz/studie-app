import SwiftUI

/// Renders a bundled Markdown legal document (headings, bullets, paragraphs with inline formatting).
struct LegalDocumentView: View {
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
        .navigationTitle(document.title)
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
        for raw in document.markdown.components(separatedBy: .newlines) {
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
    var body: some View {
        List {
            Section {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink {
                        LegalDocumentView(document: document)
                    } label: {
                        Label(document.title, systemImage: document.symbol)
                    }
                }
            } footer: {
                Text("Version \(LegalDocument.currentVersion). Questions? \(AppConfig.supportEmail)")
            }
        }
        .navigationTitle("Legal")
    }
}

/// Shown when the signed-in user hasn't accepted the current terms (new account via Apple/Google, or updated terms).
struct TermsAcceptanceView: View {
    @Environment(AppState.self) private var app
    @State private var agreed = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SonoraLogo(size: 22)
                        Text(app.account?.acceptedTermsVersion == nil ? "Before you start" : "We've updated our terms")
                            .font(.title2.bold())
                        Text("Please read and accept the documents below to use Sonora.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(LegalDocument.required(for: app.role)) { document in
                        NavigationLink {
                            LegalDocumentView(document: document)
                        } label: {
                            Label(document.title, systemImage: document.symbol)
                        }
                    }
                }
                Section {
                    Toggle("I have read and accept these documents", isOn: $agreed)
                } footer: {
                    Text("We record the version and time of your acceptance. You can withdraw consent by deleting your account in Settings.")
                }
            }
            .navigationTitle("Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await app.signOut() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") {
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            do { app.updateAccount(try await app.backend.acceptTerms(version: LegalDocument.currentVersion)) }
                            catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(!agreed || isSaving)
                }
            }
            .errorAlert($error)
        }
    }
}

/// GDPR: lets the user download everything Sonora stores about them.
struct DataExportButton: View {
    @Environment(AppState.self) private var app
    @State private var fileURL: URL?
    @State private var isExporting = false
    @State private var error: String?

    var body: some View {
        Group {
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share my data file", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    export()
                } label: {
                    Label(isExporting ? "Preparing…" : "Download my data", systemImage: "arrow.down.doc")
                }
                .disabled(isExporting)
            }
        }
        .errorAlert($error)
    }

    private func export() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await app.backend.exportPersonalData()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("sonora-data-\(Date.now.formatted(.iso8601.year().month().day())).json")
                try data.write(to: url, options: .completeFileProtection)
                fileURL = url
            } catch { self.error = error.userMessage }
        }
    }
}
