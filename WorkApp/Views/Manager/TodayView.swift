import SwiftUI

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @State private var editingBlock: TimeBlock?
    @State private var addingReminder = false

    private var checklist: [ChecklistItem] { state.checklist.sorted { $0.order < $1.order } }
    private var openReminders: [Reminder] { state.reminders.filter { !$0.isDone }.sorted { $0.dueAt < $1.dueAt } }

    var body: some View {
        List {
            // Daily checklist
            Section {
                ProgressHeader(done: checklist.filter { $0.isDone(on: state.today) }.count,
                               total: checklist.count, label: "Today's checklist")
                ForEach(checklist) { item in
                    let done = item.isDone(on: state.today)
                    Button { Task { await state.toggle(item) } } label: {
                        HStack {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? Theme.ok : .secondary).font(.title3)
                            VStack(alignment: .leading) {
                                Text(item.title).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                                if let who = item.completions[state.today] {
                                    Text("Done by \(who)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await state.remove(item, \.checklist) } } }
                }
                AddRow(placeholder: "Add checklist item") { title in
                    await state.upsert(ChecklistItem(title: title, order: state.checklist.count), \.checklist)
                }
            }

            // Reminders
            Section {
                ForEach(openReminders) { r in
                    HStack {
                        Button { var d = r; d.isDone = true; Task { await state.upsert(d, \.reminders) } } label: {
                            Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                        }.buttonStyle(.borderless)
                        VStack(alignment: .leading) {
                            Text(r.title)
                            if !r.notes.isEmpty { Text(r.notes).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(r.dueAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(r.dueAt < Date() ? Theme.alert : .secondary)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await state.remove(r, \.reminders) } } }
                }
                Button { addingReminder = true } label: { Label("Add reminder", systemImage: "bell.badge") }
            } header: { Text("Reminders") }

            // Important times
            Section {
                ForEach(state.timeBlocks.sorted { $0.startMinutes < $1.startMinutes }) { b in
                    Button { editingBlock = b } label: {
                        HStack {
                            Image(systemName: "clock.fill").foregroundStyle(b.isActive() ? Theme.alert : Theme.accent)
                            VStack(alignment: .leading) {
                                Text(b.title).foregroundStyle(.primary)
                                Text("\(b.rangeLabel) · \(b.daysLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if b.isActive() { Text("NOW").font(.caption.bold()).foregroundStyle(Theme.alert) }
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await state.remove(b, \.timeBlocks) } } }
                }
                if state.timeBlocks.isEmpty {
                    Button("Add 5:00–7:30 PM line lock") { Task { await state.upsert(TimeBlock.lineLock, \.timeBlocks) } }
                }
                Button { editingBlock = TimeBlock(title: "", startMinutes: 17 * 60, endMinutes: 19 * 60) } label: {
                    Label("Add important time", systemImage: "plus")
                }
            } header: { Text("Important times") }
        }
        .safeAreaInset(edge: .top) { TimeBlockBanner() }
        .navigationTitle("Today")
        .refreshable { await state.refreshAll() }
        .sheet(item: $editingBlock) { TimeBlockEditor(block: $0) }
        .sheet(isPresented: $addingReminder) { ReminderEditor() }
    }
}

struct TimeBlockEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var block: TimeBlock
    init(block: TimeBlock) { _block = State(initialValue: block) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (e.g. Line lock)", text: $block.title)
                    TextField("Details (e.g. Crew stays on the line)", text: $block.detail)
                }
                Section {
                    DatePicker("Starts", selection: minutes(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: minutes(\.endMinutes), displayedComponents: .hourAndMinute)
                    Toggle("Notify at start and end", isOn: $block.notify)
                }
                Section("Days") {
                    ForEach(1...7, id: \.self) { d in
                        Toggle(Calendar.current.weekdaySymbols[d - 1], isOn: Binding(
                            get: { block.weekdays.contains(d) },
                            set: { on in if on { block.weekdays.append(d) } else { block.weekdays.removeAll { $0 == d } } }))
                    }
                }
            }
            .navigationTitle("Important time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await state.upsert(block, \.timeBlocks); dismiss() } }
                        .disabled(block.title.isEmpty || block.endMinutes <= block.startMinutes || block.weekdays.isEmpty)
                }
            }
        }
    }

    private func minutes(_ kp: WritableKeyPath<TimeBlock, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(block[keyPath: kp] * 60)) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                block[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

struct ReminderEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reminder = Reminder(title: "", dueAt: Date().addingTimeInterval(3600))

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs to happen?", text: $reminder.title)
                TextField("Notes", text: $reminder.notes, axis: .vertical)
                DatePicker("When", selection: $reminder.dueAt)
            }
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        reminder.createdBy = state.userName
                        Task { await state.upsert(reminder, \.reminders); dismiss() }
                    }.disabled(reminder.title.isEmpty)
                }
            }
        }
    }
}
