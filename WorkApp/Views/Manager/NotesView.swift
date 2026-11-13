import SwiftUI

struct NotesView: View {
    @EnvironmentObject var state: AppState

    private var open: [Note] { state.notes.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt } }
    private var done: [Note] { state.notes.filter(\.isDone).sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        List {
            Section {
                AddRow(placeholder: "New to-do or note") { text in
                    await state.upsert(Note(text: text, createdBy: state.userName), \.notes)
                }
                ForEach(open) { row($0) }
            }
            if !done.isEmpty {
                Section("Done") { ForEach(done) { row($0) } }
            }
        }
        .safeAreaInset(edge: .top) { TimeBlockBanner() }
        .navigationTitle("Notes")
        .refreshable { await state.refreshAll() }
    }

    private func row(_ note: Note) -> some View {
        HStack(alignment: .top) {
            Button { var n = note; n.isDone.toggle(); Task { await state.upsert(n, \.notes) } } label: {
                Image(systemName: note.isDone ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundStyle(note.isDone ? Theme.ok : .secondary)
            }.buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).strikethrough(note.isDone).foregroundStyle(note.isDone ? .secondary : .primary)
                Text("\(note.createdBy) · \(note.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions { Button("Delete", role: .destructive) { Task { await state.remove(note, \.notes) } } }
    }
}
