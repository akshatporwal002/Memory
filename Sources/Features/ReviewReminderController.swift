import Foundation
import Observation
import UserNotifications

/// Device-local reminder. A single stable identifier replaces every previous time.
@MainActor @Observable public final class ReviewReminderController {
    public var enabled: Bool { didSet { defaults.set(enabled, forKey: "engram.reminder.enabled"); reconcile() } }
    public var time: Date { didSet { let parts = Calendar.current.dateComponents([.hour, .minute], from: time); defaults.set(parts.hour ?? 19, forKey: "engram.reminder.hour"); defaults.set(parts.minute ?? 0, forKey: "engram.reminder.minute"); reconcile() } }
    public private(set) var status: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: Task<Void, Never>?
    private static let identifier = "engram.daily-review"
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "engram.reminder.enabled")
        let hour = defaults.object(forKey: "engram.reminder.hour") as? Int ?? 19
        let minute = defaults.integer(forKey: "engram.reminder.minute")
        time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
    public func reconcile() {
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            guard enabled else { status = nil; return }
            // UI fixtures never request OS permissions or create real reminders.
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { status = "Daily reminder preview"; return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard enabled else { return }
                guard granted else { status = "Notifications are disabled. Allow Engram notifications in system settings."; return }
                let content = UNMutableNotificationContent()
                content.title = "A moment to review"
                content.body = "Your learning is waiting. Open Engram when you’re ready."
                content.sound = .default
                let components = DateComponents(hour: defaults.object(forKey: "engram.reminder.hour") as? Int ?? 19, minute: defaults.integer(forKey: "engram.reminder.minute"))
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
                status = nil
            } catch { status = "Couldn’t schedule your reminder: " + error.localizedDescription }
        }
    }
}
