import SwiftUI

struct ClosingManagerView: View {
    @EnvironmentObject var state: AppState
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Review photos").tag(0)
                Text("Set up tasks").tag(1)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .bottom])
            if mode == 0 { ClosingReviewList() } else { ClosingSetupList() }
        }
        .safeAreaInset(edge: .top) { TimeBlockBanner() }
        .navigationTitle("Closing")
        .navigationDestination(for: ClosingTask.self) { ReviewDetailView(task: $0) }
        .task { // auto-refresh so new photos show up without leaving the office
            while !Task.isCancelled {
                await state.refreshClosing()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
}

struct ClosingReviewList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let tasks = state.tonightTasks
        let subs = tasks.compactMap { state.submission(for: $0) }
        List {
            Section {
                ProgressHeader(done: subs.filter { $0.status == .approved }.count, total: tasks.count,
                               label: "Approved tonight")
                HStack(spacing: 16) {
                    Label("\(subs.filter { $0.status == .pending }.count) waiting", systemImage: "hourglass")
                        .foregroundStyle(Theme.warn)
                    Label("\(subs.filter { $0.status == .redo }.count) redo", systemImage: "arrow.uturn.backward")
                        .foregroundStyle(Theme.alert)
                    Label("\(tasks.count - subs.count) not sent", systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
            }
            ForEach(state.byStation(tasks), id: \.station) { group in
                Section(group.station) {
                    ForEach(group.tasks) { task in
                        let sub = state.submission(for: task)
                        NavigationLink(value: task) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                    if let sub {
                                        Text("\(sub.crewName) · \(sub.submittedAt.shortTime)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                StatusChip(status: sub?.status)
                            }
                        }
                    }
                }
            }
            if tasks.isEmpty {
                ContentUnavailableCompat(title: "No closing tasks", message: "Add them under “Set up tasks”.")
            }
        }
        .refreshable { await state.refreshClosing() }
    }
}

struct ReviewDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let task: ClosingTask
    @State private var comment = ""

    var body: some View {
        let sub = state.submission(for: task)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(task.station).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    StatusChip(status: sub?.status)
                }
                if !task.instructions.isEmpty {
                    Text(task.instructions).font(.subheadline).foregroundStyle(.secondary)
                }
                if let sub {
                    SubmissionPhoto(submission: sub)
                    Text("Sent by \(sub.crewName) at \(sub.submittedAt.shortTime)")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Note for crew (what to fix)", text: $comment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 12) {
                        Button { Task { await state.review(sub, approved: false, comment: comment); dismiss() } } label: {
                            Label("Redo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(Theme.alert).controlSize(.large)
                        Button { Task { await state.review(sub, approved: true, comment: comment); dismiss() } } label: {
                            Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.ok).controlSize(.large)
                    }
                } else {
                    Text("No photo yet. It will show up here automatically.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding()
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { comment = sub?.managerComment ?? "" }
    }
}

struct ClosingSetupList: View {
    @EnvironmentObject var state: AppState
    @State private var editing: ClosingTask?

    var body: some View {
        let nightly = state.closingTasks.filter { $0.oneOffDay == nil }
        let tonight = state.closingTasks.filter { $0.oneOffDay == state.today }
        List {
            Section {
                ForEach(state.byStation(nightly), id: \.station) { group in
                    ForEach(group.tasks) { taskRow($0) }
                }
                Button { editing = ClosingTask(title: "") } label: { Label("Add nightly task", systemImage: "plus") }
            } header: { Text("Every night") }

            Section {
                ForEach(tonight) { taskRow($0) }
                Button { editing = ClosingTask(title: "", oneOffDay: state.today) } label: {
                    Label("Add task for tonight", systemImage: "plus")
                }
            } header: { Text("Tonight only") } footer: {
                Text("Crew see new tasks within a few seconds, even after close.")
            }
        }
        .sheet(item: $editing) { ClosingTaskEditor(task: $0) }
    }

    private func taskRow(_ t: ClosingTask) -> some View {
        Button { editing = t } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).foregroundStyle(.primary)
                Text(t.station).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions { Button("Delete", role: .destructive) { Task { await state.remove(t, \.closingTasks) } } }
    }
}

struct ClosingTaskEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var task: ClosingTask
    private let isNew: Bool
    init(task: ClosingTask) { _task = State(initialValue: task); isNew = task.title.isEmpty }

    private var tonightOnly: Binding<Bool> {
        Binding(get: { task.oneOffDay != nil }, set: { task.oneOffDay = $0 ? state.today : nil })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task (e.g. Clean and wrap the grill)", text: $task.title)
                    TextField("Station (e.g. Grill, Line, Dish, Front)", text: $task.station)
                    TextField("What the photo should show", text: $task.instructions, axis: .vertical)
                }
                if !state.stations.isEmpty {
                    Section("Stations") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(state.stations, id: \.self) { s in
                                    Button(s) { task.station = s }.buttonStyle(.bordered)
                                        .tint(task.station == s ? Theme.accent : .gray)
                                }
                            }
                        }
                    }
                }
                Toggle("Tonight only", isOn: tonightOnly)
            }
            .navigationTitle(isNew ? "New closing task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew {
                            task.createdBy = state.userName
                            task.order = state.closingTasks.count
                            let h = Calendar.current.component(.hour, from: Date())
                            task.addedAfterClose = task.oneOffDay != nil && (h >= Config.closingHour || h < BusinessDay.cutoffHour)
                        }
                        Task { await state.upsert(task, \.closingTasks); dismiss() }
                    }.disabled(task.title.isEmpty)
                }
            }
        }
    }
}
