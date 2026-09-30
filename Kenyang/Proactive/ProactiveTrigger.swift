import BackgroundTasks
import CoreLocation
import EventKit
import Foundation
import UserNotifications

/// Arrival at a known venue, or a booking on today's calendar, runs `ProactiveDecision`
/// and posts only when it has something to say.
@MainActor
final class ProactiveTrigger: NSObject {
    static let shared = ProactiveTrigger()

    static let morningTaskIdentifier = "com.hansjoachim.Kenyang.morning"

    private let locations = CLLocationManager()
    private var monitorTask: Task<Void, Never>?
    private weak var store: KenyangStore?

    private let radius: CLLocationDistance = 150

    private override init() { super.init() }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "proactive.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "proactive.enabled") }
    }

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

    /// Records where a venue is, if location was already granted. Never prompts.
    func noteLocation(of restaurant: Restaurant) {
        let status = locations.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse,
              let here = locations.location else { return }
        restaurant.latitude = here.coordinate.latitude
        restaurant.longitude = here.coordinate.longitude
    }

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
                print("Region monitoring ended: \(error)")
            }
        }
    }

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

    func evaluate(venueNamed name: String, source: String) async {
        guard let store, let venue = store.restaurant(named: name) else { return }

        switch ProactiveDecision.decide(for: venue) {
        case .notify(let title, let body):
            await post(title: title, body: body)
        case .silent(let reason):
            print("Proactive \(source) at \(name): silent, \(reason.explanation)")
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
