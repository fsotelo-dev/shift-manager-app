import Foundation

/// Every synced model conforms to this. Stored as JSON in a single CloudKit field,
/// so adding a property never needs a schema migration.
protocol Record: Codable, Identifiable, Hashable {
    static var recordType: String { get }
    var id: String { get }
    /// Extra plain fields copied onto the CloudKit record so they can be queried.
    var indexFields: [String: String] { get }
}
extension Record { var indexFields: [String: String] { [:] } }

enum Role: String, Codable, CaseIterable { case manager, crew }

/// Closing runs past midnight, so anything before 4 AM counts as the previous day.
enum BusinessDay {
    static var cutoffHour = 4
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(for date: Date = Date()) -> String {
        fmt.string(from: date.addingTimeInterval(TimeInterval(-cutoffHour * 3600)))
    }
}

struct InventoryItem: Record {
    static let recordType = "InventoryItem"
    var id = UUID().uuidString
    var name: String
    var category: String = "General"
    var unit: String = "case"
    var par: Double = 0
    var onHand: Double = 0
    var lastCountedAt: Date?
    var lastCountedBy: String?
    var needsOrder: Bool { onHand < par }
    var orderQty: Double { max(0, par - onHand) }
}

struct Reminder: Record {
    static let recordType = "Reminder"
    var id = UUID().uuidString
    var title: String
    var notes: String = ""
    var dueAt: Date
    var isDone = false
    var createdBy: String = ""
}

struct Note: Record {
    static let recordType = "Note"
    var id = UUID().uuidString
    var text: String
    var isDone = false
    var createdAt = Date()
    var createdBy: String = ""
}

/// Repeats every day; completion is tracked per business day.
struct ChecklistItem: Record {
    static let recordType = "ChecklistItem"
    var id = UUID().uuidString
    var title: String
    var order: Int = 0
    var completions: [String: String] = [:] // day key -> who checked it
    func isDone(on day: String) -> Bool { completions[day] != nil }
}

/// A recurring window like "Line lock 5:00–7:30 PM: crew stays on the line".
struct TimeBlock: Record {
    static let recordType = "TimeBlock"
    var id = UUID().uuidString
    var title: String
    var detail: String = ""
    var startMinutes: Int // minutes after midnight
    var endMinutes: Int
    var weekdays: [Int] = Array(1...7) // Calendar weekday, 1 = Sunday
    var notify = true

    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, weekdays.contains(wd) else { return false }
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m >= startMinutes && m < endMinutes
    }
    static func label(_ minutes: Int) -> String {
        Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(Double(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }
    var rangeLabel: String { "\(Self.label(startMinutes)) – \(Self.label(endMinutes))" }
    var daysLabel: String {
        if weekdays.count == 7 { return "Every day" }
        let s = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { s[$0 - 1] }.joined(separator: ", ")
    }

    static let lineLock = TimeBlock(title: "Line lock", detail: "Crew can't leave the line",
                                    startMinutes: 17 * 60, endMinutes: 19 * 60 + 30)
}

/// A closing task the manager sets. `oneOffDay == nil` means it repeats every night.
struct ClosingTask: Record {
    static let recordType = "ClosingTask"
    var id = UUID().uuidString
    var title: String
    var station: String = "General"
    var instructions: String = ""
    var oneOffDay: String?
    var addedAfterClose = false
    var createdBy: String = ""
    var order: Int = 0
}

enum ReviewStatus: String, Codable { case pending, approved, redo }

/// One photo per task per night. The id is fixed so a redo replaces the old photo.
struct ClosingSubmission: Record {
    static let recordType = "ClosingSubmission"
    var id: String
    var taskId: String
    var day: String
    var crewName: String
    var submittedAt = Date()
    var status: ReviewStatus = .pending
    var managerComment: String = ""
    var reviewedBy: String?
    var reviewedAt: Date?

    static func makeID(day: String, taskId: String) -> String { "\(day)_\(taskId)" }
    var indexFields: [String: String] { ["day": day, "status": status.rawValue] }
}

extension JSONEncoder {
    static let store: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
extension JSONDecoder {
    static let store: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
