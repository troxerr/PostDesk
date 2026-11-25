import Foundation
import Observation
import UserNotifications

/// A daily nudge to post your replies by hand, the part that can't be automated.
/// Settings > Writing > Daily reminder.
@Observable
final class Reminder {
    static let shared = Reminder()
    private static let id = "daily-replies"

    var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: "reminder.on")
            schedule()
        }
    }

    /// Minutes after midnight, in this Mac's time zone.
    var minutes: Int {
        didSet {
            UserDefaults.standard.set(minutes, forKey: "reminder.minutes")
            schedule()
        }
    }

    var time: Date {
        get { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private init() {
        isOn = UserDefaults.standard.bool(forKey: "reminder.on")
        minutes = UserDefaults.standard.object(forKey: "reminder.minutes") as? Int ?? 7 * 60 + 45
    }

    func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        guard isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for today's replies"
        content.body = "Draft replies in PostDesk and post the good ones yourself. Early replies are where new followers find you."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
        let request = UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger)
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.add(request)
    }
}
