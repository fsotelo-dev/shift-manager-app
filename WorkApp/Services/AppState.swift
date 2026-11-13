import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var role: Role? { didSet { UserDefaults.standard.set(role?.rawValue, forKey: "role") } }
    @Published var userName: String { didSet { UserDefaults.standard.set(userName, forKey: "userName") } }

    @Published var inventory: [InventoryItem] = []
    @Published var reminders: [Reminder] = []
    @Published var notes: [Note] = []
    @Published var checklist: [ChecklistItem] = []
    @Published var timeBlocks: [TimeBlock] = []
    @Published var closingTasks: [ClosingTask] = []
    @Published var submissions: [ClosingSubmission] = []
    @Published var lastError: String?

    let store: DataStore
    private var photoCache: [String: Data] = [:]

    init(store: DataStore) {
        self.store = store
        role = UserDefaults.standard.string(forKey: "role").flatMap(Role.init)
        userName = UserDefaults.standard.string(forKey: "userName") ?? ""
    }

    var today: String { BusinessDay.key() }

    // MARK: Loading

    func refreshAll() async {
        do {
            async let blocks = store.fetchAll(TimeBlock.self)
            async let tasks = store.fetchAll(ClosingTask.self)
            async let subs = store.fetch(ClosingSubmission.self, match: ("day", today))
            timeBlocks = try await blocks
            closingTasks = try await tasks
            submissions = try await subs
            if role == .manager {
                async let inv = store.fetchAll(InventoryItem.self)
                async let rem = store.fetchAll(Reminder.self)
                async let nts = store.fetchAll(Note.self)
                async let chk = store.fetchAll(ChecklistItem.self)
                inventory = try await inv
                reminders = try await rem
                notes = try await nts
                checklist = try await chk
                if let ck = store as? CloudKitStore { await ck.subscribeToPendingSubmissions() }
            }
            await rescheduleNotifications()
        } catch { lastError = error.localizedDescription }
    }

    /// Lighter refresh used by the closing screens' auto-refresh loop.
    func refreshClosing() async {
        do {
            closingTasks = try await store.fetchAll(ClosingTask.self)
            submissions = try await store.fetch(ClosingSubmission.self, match: ("day", today))
        } catch { lastError = error.localizedDescription }
    }

    func rescheduleNotifications() async {
        await Notifier.reschedule(reminders: role == .manager ? reminders : [], blocks: timeBlocks)
    }

    // MARK: Generic save / delete (updates the screen right away, then syncs)

    func upsert<T: Record>(_ item: T, _ list: ReferenceWritableKeyPath<AppState, [T]>, photo: Data? = nil) async {
        if let i = self[keyPath: list].firstIndex(where: { $0.id == item.id }) { self[keyPath: list][i] = item }
        else { self[keyPath: list].append(item) }
        do { try await store.save(item, photo: photo) } catch { lastError = error.localizedDescription }
        if T.self == Reminder.self || T.self == TimeBlock.self { await rescheduleNotifications() }
    }

    func remove<T: Record>(_ item: T, _ list: ReferenceWritableKeyPath<AppState, [T]>) async {
        self[keyPath: list].removeAll { $0.id == item.id }
        do { try await store.delete(T.self, id: item.id) } catch { lastError = error.localizedDescription }
        if T.self == Reminder.self || T.self == TimeBlock.self { await rescheduleNotifications() }
    }

    // MARK: Today

    func activeBlock(at date: Date = Date()) -> TimeBlock? { timeBlocks.first { $0.isActive(at: date) } }

    func toggle(_ item: ChecklistItem) async {
        var i = item
        if i.isDone(on: today) { i.completions[today] = nil } else { i.completions[today] = userName }
        let cutoff = BusinessDay.key(for: Date().addingTimeInterval(-30 * 86400))
        i.completions = i.completions.filter { $0.key >= cutoff } // keep 30 days of history
        await upsert(i, \.checklist)
    }

    // MARK: Closing

    var tonightTasks: [ClosingTask] {
        closingTasks.filter { $0.oneOffDay == nil || $0.oneOffDay == today }
            .sorted { ($0.station, $0.order, $0.title) < ($1.station, $1.order, $1.title) }
    }

    var stations: [String] { Array(Set(tonightTasks.map(\.station))).sorted() }

    func byStation(_ tasks: [ClosingTask]) -> [(station: String, tasks: [ClosingTask])] {
        Dictionary(grouping: tasks, by: \.station).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func submission(for task: ClosingTask) -> ClosingSubmission? {
        let id = ClosingSubmission.makeID(day: today, taskId: task.id)
        return submissions.first { $0.id == id }
    }

    func submit(_ task: ClosingTask, photo: Data) async {
        let sub = ClosingSubmission(id: ClosingSubmission.makeID(day: today, taskId: task.id),
                                    taskId: task.id, day: today, crewName: userName)
        await upsert(sub, \.submissions, photo: photo)
    }

    func review(_ sub: ClosingSubmission, approved: Bool, comment: String) async {
        var s = sub
        s.status = approved ? .approved : .redo
        s.managerComment = comment
        s.reviewedBy = userName
        s.reviewedAt = Date()
        await upsert(s, \.submissions)
    }

    func photo(for sub: ClosingSubmission) async -> Data? {
        let key = "\(sub.id)-\(sub.submittedAt.timeIntervalSince1970)"
        if let d = photoCache[key] { return d }
        let d = try? await store.photo(ClosingSubmission.self, id: sub.id)
        if let d { photoCache[key] = d }
        return d
    }

    func signOut() { role = nil }
}
