import Foundation
import UserNotifications

/// Local notifications for reminders and time blocks (start + end, weekly).
enum Notifier {
    static func requestAuth() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func reschedule(reminders: [Reminder], blocks: [TimeBlock]) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("rem-") || $0.hasPrefix("tb-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // iOS keeps at most 64 pending notifications; leave room for time blocks.
        let upcoming = reminders.filter { !$0.isDone && $0.dueAt > Date() }.sorted { $0.dueAt < $1.dueAt }.prefix(30)
        for r in upcoming {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.dueAt)
            add(id: "rem-\(r.id)", title: r.title, body: r.notes.isEmpty ? "Reminder" : r.notes,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        for b in blocks where b.notify {
            for wd in b.weekdays {
                for (edge, minutes, verb) in [("s", b.startMinutes, "starts now"), ("e", b.endMinutes, "is over")] {
                    let comps = DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: wd)
                    add(id: "tb-\(b.id)-\(edge)\(wd)", title: "\(b.title) \(verb)", body: b.detail,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
                }
            }
        }
    }

    private static func add(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
