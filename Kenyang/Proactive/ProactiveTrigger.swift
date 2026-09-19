import BackgroundTasks
import CoreLocation
import EventKit
import Foundation
import UserNotifications

/// The arrival and morning-of triggers — `BUFFET.md` §10b.
///
/// ```
/// region monitoring on visited venues   (arrival)
/// EventKit scan for restaurant events   (morning of)
///         ↓
/// TierEngine.verdict — enough history to argue from?
///         ↓
///  ├─ nothing earned to say  → SILENCE, with a reason
///  └─ a tier worth changing  → one line, before you order
/// ```
///
/// **The restraint is the feature.** The recommendation only saves anything if it arrives
/// *before* the tier is bought, which is why the trigger exists at all; and a trigger that
/// notified every time would be a scheduler wearing an agent's clothes.
///
/// Everything here is plumbing. The decision is `ProactiveDecision`, which is pure and is
/// what the battery tests — this type can only be exercised on a device with a real
/// region crossing, and `TESTS.md` T38 says so.
@MainActor
final class ProactiveTrigger: NSObject {
    static let shared = ProactiveTrigger()

    /// Registered in `KenyangApp.init` and declared in `Kenyang-Info.plist`. Registration
    /// must happen before the app finishes launching or `BGTaskScheduler` throws.
    static let morningTaskIdentifier = "com.hansjoachim.Kenyang.morning"

    private let locations = CLLocationManager()
    private var monitorTask: Task<Void, Never>?
    private weak var store: KenyangStore?

    /// A venue is watched from 150 m out — far enough to fire while you are still
    /// deciding what to order, close enough not to trip from across the street.
    private let radius: CLLocationDistance = 150

    private override init() { super.init() }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "proactive.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "proactive.enabled") }
    }

    // MARK: - Turning it on

    /// Asks for what the trigger needs, once, and arms whatever it is granted. Each
    /// permission is independent: no notifications means nothing can be delivered, no
    /// location means only the calendar path runs, no calendar means only arrival does.
    func enable(store: KenyangStore) async {
        self.store = store
        let notify = await requestNotifications()
        guard notify else { return }

        isEnabled = true
        locations.delegate = self
        locations.requestAlwaysAuthorization()

        await armRegions(store: store)
        scheduleMorningScan()
    }

    func disable() {
        isEnabled = false
        monitorTask?.cancel()
        monitorTask = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.morningTaskIdentifier)
    }

    private func requestNotifications() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Record where a venue is the first time a meal is eaten there. No prompt of its
    /// own: if location was never granted this returns nothing and the arrival trigger
    /// simply never arms for that venue.
    func noteLocation(of restaurant: Restaurant) {
        let status = locations.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse,
              let here = locations.location else { return }
        restaurant.latitude = here.coordinate.latitude
        restaurant.longitude = here.coordinate.longitude
    }

    // MARK: - Arrival

    private func armRegions(store: KenyangStore) async {
        let venues = store.allRestaurants().filter { $0.latitude != nil && $0.longitude != nil }
        guard !venues.isEmpty else { return }

        let conditions = venues.map { venue in
            (venue.name,
             CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: venue.latitude!, longitude: venue.longitude!),
                radius: radius))
        }

        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            let monitor = await CLMonitor("KenyangVenues")
            for (name, condition) in conditions {
                await monitor.add(condition, identifier: name)
            }
            do {
                for try await event in await monitor.events {
                    guard event.state == .satisfied else { continue }
                    await self?.evaluate(venueNamed: event.identifier, source: "arrival")
                }
            } catch {
                // The stream ends when monitoring is revoked or the app is jetsammed.
                // Nothing to recover: the next launch re-arms from the store.
                print("[PROACTIVE] region monitoring ended — \(error)")
            }
        }
    }

    // MARK: - Morning of

    /// Registered once at launch. The scan runs, decides, and in the common case posts
    /// nothing — see `ProactiveDecision`.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: morningTaskIdentifier,
                                        using: nil) { task in
            Task { @MainActor in
                await ProactiveTrigger.shared.runMorningScan()
                ProactiveTrigger.shared.scheduleMorningScan()
                task.setTaskCompleted(success: true)
            }
        }
    }

    func scheduleMorningScan() {
        let request = BGAppRefreshTaskRequest(identifier: Self.morningTaskIdentifier)
        request.earliestBeginDate = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 9),
            matchingPolicy: .nextTime)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Look for a booking today at a venue we know, and evaluate that venue.
    func runMorningScan() async {
        guard let store, isEnabled else { return }
        let names = Set(store.allRestaurants().map { $0.name.lowercased() })
        guard !names.isEmpty else { return }

        let events = EKEventStore()
        guard (try? await events.requestFullAccessToEvents()) == true else { return }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = events.predicateForEvents(withStart: start, end: end, calendars: nil)

        for event in events.events(matching: predicate) {
            let title = (event.title ?? "").lowercased()
            guard let match = names.first(where: { title.contains($0) }) else { continue }
            await evaluate(venueNamed: match, source: "booking")
            return
        }
    }

    // MARK: - The decision

    /// Runs the gate and posts **only** if there is something earned to say.
    func evaluate(venueNamed name: String, source: String) async {
        guard let store, let venue = store.restaurant(named: name) else { return }

        switch ProactiveDecision.decide(for: venue) {
        case .notify(let title, let body):
            await post(title: title, body: body)
        case .silent(let reason):
            // Recorded, never delivered. A silence that leaves no trace cannot be told
            // apart from a trigger that failed to fire.
            print("[PROACTIVE] \(source) at \(name) → silent: \(reason.explanation)")
        }
    }

    private func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension ProactiveTrigger: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways else { return }
        Task { @MainActor in
            guard let store = self.store else { return }
            await self.armRegions(store: store)
        }
    }
}
