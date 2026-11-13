import SwiftUI

struct CrewHome: View {
    @EnvironmentObject var state: AppState
    @AppStorage("crewStation") private var station = "All"

    var body: some View {
        let tasks = state.tonightTasks.filter { station == "All" || $0.station == station }
        let approved = tasks.filter { state.submission(for: $0)?.status == .approved }.count
        let redo = tasks.filter { state.submission(for: $0)?.status == .redo }
        NavigationStack {
            List {
                Section {
                    ProgressHeader(done: approved, total: tasks.count, label: "Closing checked off")
                    Picker("My station", selection: $station) {
                        Text("All stations").tag("All")
                        ForEach(state.stations, id: \.self) { Text($0).tag($0) }
                    }
                }
                if !redo.isEmpty {
                    Section {
                        Label("\(redo.count) task\(redo.count == 1 ? "" : "s") sent back. Fix and retake the photo.",
                              systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(Theme.alert)
                    }
                }
                ForEach(state.byStation(tasks), id: \.station) { group in
                    Section(group.station) {
                        ForEach(group.tasks) { task in
                            NavigationLink(value: task) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                        if task.addedAfterClose {
                                            Label("Added by manager tonight", systemImage: "sparkles")
                                                .font(.caption).foregroundStyle(Theme.warn)
                                        }
                                    }
                                    Spacer()
                                    StatusChip(status: state.submission(for: task)?.status)
                                }
                            }
                        }
                    }
                }
                if tasks.isEmpty {
                    ContentUnavailableCompat(title: "No closing tasks yet",
                                             message: "Your manager's tasks will show up here.")
                }
            }
            .safeAreaInset(edge: .top) { TimeBlockBanner() }
            .navigationTitle("Hi, \(state.userName)")
            .navigationDestination(for: ClosingTask.self) { CrewTaskView(task: $0) }
            .refreshable { await state.refreshClosing() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh") { Task { await state.refreshClosing() } }
                        Button("Switch user", role: .destructive) { state.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .task { // picks up manager add-ons and approvals automatically
                while !Task.isCancelled {
                    await state.refreshClosing()
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
        }
    }
}

struct CrewTaskView: View {
    @EnvironmentObject var state: AppState
    let task: ClosingTask
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var sending = false

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What to show").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(task.instructions)
                    }
                }
                if let sub, sub.status == .redo {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Redo requested\(sub.reviewedBy.map { " by \($0)" } ?? "")", systemImage: "exclamationmark.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                        if !sub.managerComment.isEmpty { Text(sub.managerComment) }
                    }
                    .foregroundStyle(Theme.alert)
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.alert.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                if let sub, sub.status == .approved {
                    Label("Approved\(sub.reviewedBy.map { " by \($0)" } ?? ""). Nice work!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.ok).font(.subheadline.weight(.semibold))
                }

                if let captured {
                    Image(uiImage: captured).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 12) {
                        Button("Retake") { showCamera = true }
                            .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                        Button {
                            guard let data = captured.jpegForUpload() else { return }
                            sending = true
                            Task {
                                await state.submit(task, photo: data)
                                sending = false
                                self.captured = nil
                            }
                        } label: {
                            (sending ? Text("Sending…") : Text("Send to manager")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(sending)
                    }
                } else {
                    if let sub { SubmissionPhoto(submission: sub) }
                    if sub?.status != .approved {
                        Button { showCamera = true } label: {
                            Label(sub == nil ? "Take photo" : "Retake photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured = $0 }.ignoresSafeArea()
        }
    }
}
