import SwiftUI

struct MessagesList: View {
    @Environment(AppStore.self) private var store
    @State private var filter = MessageFilter.all
    @State private var search = ""

    var body: some View {
        let messages = filter.apply(store.data.messages, search: search)
        List {
            Picker("Forrás", selection: $filter) {
                ForEach(MessageFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            ForEach(messages) { m in
                NavigationLink(value: m) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if m.unread {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("Olvasatlan")
                            }
                            Text(m.title).font(.headline.weight(m.unread ? .bold : .semibold)).lineLimit(1)
                            Spacer()
                            if !m.attachments.isEmpty {
                                Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel("Csatolmány")
                            }
                            Text(m.date.hu(Calendar.hu.isDate(m.date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let a = m.author { Text(a).font(.caption).foregroundStyle(.secondary) }
                        Text(m.html.strippingTags).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .overlay {
            if messages.isEmpty {
                if search.isEmpty { ContentUnavailableView("Nincs üzenet", systemImage: "envelope.open") } else { ContentUnavailableView.search(text: search) }
            }
        }
        .searchable(text: $search, prompt: "Keresés")
        .navigationTitle("Üzenetek")
        .refreshable { await store.refresh() }
    }
}

struct MessageDetail: View {
    let message: Message
    @Environment(AppStore.self) private var store
    @State private var html: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.title).font(.title2.bold())
                Text([message.author, message.date.hu("yMMMMd")].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                if failed {
                    Label("Nem sikerült letölteni a teljes üzenetet; ez csak az eleje.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Color.pending)
                    Button("Újra") { Task { await load() } }.font(.footnote)
                }
                HTMLText(html: html ?? message.html)
                if !message.attachments.isEmpty {
                    AttachmentList(attachments: message.attachments).padding(.top, 8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        // teacher messages arrive shortened in the list; fetch the whole text
        .task(id: message.id) { await load() }
    }

    private func load() async {
        do {
            if let full = try await store.fullMessage(message.id) { html = full }
            failed = false
        } catch {
            failed = !isCancellation(error)
        }
    }
}
