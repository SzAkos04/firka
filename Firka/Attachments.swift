import SwiftUI
import QuickLook

/// Attachments of a teacher message: tap to download (once, then cached) and preview with Quick Look.
struct AttachmentList: View {
    let attachments: [Attachment]
    @Environment(AppStore.self) private var store
    @State private var loading: String?
    @State private var preview: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Csatolmányok").font(.headline)
            ForEach(attachments) { a in
                Button { Task { await open(a) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: Self.icon(a.name))
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        Text(a.name).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                        if loading == a.id { ProgressView() } else { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(loading != nil)
            }
        }
        .quickLookPreview($preview)
        .alert("Nem sikerült megnyitni", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func open(_ a: Attachment) async {
        loading = a.id
        defer { loading = nil }
        do {
            preview = try await store.download(a)
        } catch KretaError.http(let code) where code == 404 || code == 500 {
            error = "Ez a fájl már nem érhető el a KRÉTA-ban (a régi csatolmányokat a KRÉTA törli)."
        } catch {
            self.error = "Nem sikerült letölteni a fájlt. Van internet?"
        }
    }

    nonisolated static func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "doc", "docx", "odt", "rtf", "txt": "doc.text"
        case "xls", "xlsx", "ods", "csv": "tablecells"
        case "ppt", "pptx", "odp": "rectangle.on.rectangle"
        case "jpg", "jpeg", "png", "heic", "gif": "photo"
        case "mov", "mp4", "m4v": "film"
        case "zip", "rar", "7z": "doc.zipper"
        default: "doc"
        }
    }
}

extension Attachment {
    /// The original name (Quick Look and sharing use it), minus anything path-like.
    var safeFileName: String {
        let name = self.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return ["", ".", ".."].contains(name) ? "fajl" : name
    }
}

extension AppStore {
    /// Downloads an attachment into Caches (kept for next time; iOS may clear it when space is low).
    func download(_ a: Attachment) async throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments/\(a.id)")
        let file = dir.appendingPathComponent(a.safeFileName)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let provider else { throw KretaError.reauth }
        let data = try await provider.download(a)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return file
    }
}
