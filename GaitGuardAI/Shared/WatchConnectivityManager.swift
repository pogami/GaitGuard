// WatchConnectivityManager.swift
// Shared between watch + iPhone to sync assist events.
import Foundation
import WatchConnectivity
import Combine

struct AssistEvent: Codable {
    let timestamp: Date
    let type: String // "start" or "turn"
}

struct LiveTelemetry: Codable, Equatable {
    let timestamp: Date
    let guardState: String
    let cadenceHz: Double
    let turnRateRadPerSec: Double
    let movementIntensity: Double
}

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var assistEvents: [AssistEvent] = []
    @Published var remoteState: String = "off"
#if os(iOS)
    @Published var lastTelemetry: LiveTelemetry?
    @Published var lastTelemetryReceivedAt: Date?
#endif
#if os(watchOS)
    /// Latest known state on the watch (used to answer iPhone "refresh" requests).
    @Published private(set) var localState: String = "off"
#endif
    
    private let session: WCSession?
    private let eventsKey = "gaitguard.assistEvents"
    private var pendingGuardState: String?
#if os(iOS)
    private var demoTimer: Timer?
#endif

    // MARK: - Debug helpers

    var wcActivationStateLabel: String {
        guard let session else { return "unsupported" }
        switch session.activationState {
        case .notActivated: return "notActivated"
        case .inactive: return "inactive"
        case .activated: return "activated"
        @unknown default: return "unknown"
        }
    }

    var wcIsReachable: Bool { session?.isReachable ?? false }

#if os(iOS)
    var wcIsPaired: Bool { session?.isPaired ?? false }
    var wcIsWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
#endif
    
    override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
        
        session?.delegate = self
        session?.activate()
        
        loadEvents()
#if os(iOS)
        // If the watch already sent application context before the iPhone launched, hydrate immediately.
        hydrateFromApplicationContext()
#endif
    }
    
    // MARK: - Watch → iPhone (send from watch)
    
    func sendAssistEvent(type: String) {
        guard let session = session else { return }
        guard session.activationState == .activated else { return }
        
        let event = AssistEvent(timestamp: Date(), type: type)
        guard let data = try? JSONEncoder().encode(event) else { return }
        
        if session.isReachable {
            session.sendMessage(["assistEvent": data], replyHandler: nil) { [weak self] _ in
                // If instant delivery fails, fall back to app context.
                self?.updateApplicationContextMerging(["assistEvent": data])
            }
        } else {
            updateApplicationContextMerging(["assistEvent": data])
        }
    }

    func sendStateUpdate(_ state: String) {
        guard let session = session else { return }
#if os(watchOS)
        localState = state
#endif
        guard session.activationState == .activated else {
            // Session not yet ready — buffer the latest state and flush on activation.
            pendingGuardState = state
            return
        }
        
        // Best-effort: send immediately if reachable.
        if session.isReachable {
            session.sendMessage(["guardState": state], replyHandler: nil) { [weak self] _ in
                // If instant delivery fails, fall back to app context.
                self?.updateApplicationContextMerging(["guardState": state])
            }
        }
        // Reliable fallback: update application context (delivered even if the other app is backgrounded).
        updateApplicationContextMerging(["guardState": state])
    }

    func sendTelemetry(_ telemetry: LiveTelemetry) {
        guard let session = session else { return }
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(telemetry) else { return }

        if session.isReachable {
            session.sendMessage(["telemetry": data], replyHandler: nil) { [weak self] _ in
                self?.updateApplicationContextMerging(["telemetry": data])
            }
        } else {
            updateApplicationContextMerging(["telemetry": data])
        }
    }

    private func updateApplicationContextMerging(_ updates: [String: Any]) {
        guard let session = session else { return }
        // IMPORTANT: updateApplicationContext replaces the entire dictionary.
        // Merge with existing context so "guardState" and "assistEvent" don't overwrite each other.
        var merged = session.receivedApplicationContext
        for (k, v) in updates { merged[k] = v }
        try? session.updateApplicationContext(merged)
    }

    private func flushPendingStateIfNeeded() {
        guard let session = session else { return }
        guard session.activationState == .activated else { return }
        guard let state = pendingGuardState else { return }
        pendingGuardState = nil
        sendStateUpdate(state)
    }

#if os(iOS)
    private func hydrateFromApplicationContext() {
        guard let session = session else { return }
        if let state = session.receivedApplicationContext["guardState"] as? String {
            remoteState = state
        }
        if let data = session.receivedApplicationContext["telemetry"] as? Data,
           let decoded = try? JSONDecoder().decode(LiveTelemetry.self, from: data) {
            lastTelemetry = decoded
            lastTelemetryReceivedAt = Date()
        }
    }

    /// Ask the watch for its current guard state (useful if the iPhone launched after the watch started).
    func requestCurrentStateFromWatch() {
        guard let session = session else { return }
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }

        session.sendMessage(["requestState": true], replyHandler: { [weak self] reply in
            guard let self else { return }
            if let state = reply["guardState"] as? String {
                DispatchQueue.main.async { self.remoteState = state }
            }
        }, errorHandler: nil)
    }

    func requestTelemetryFromWatch() {
        guard let session = session else { return }
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }

        session.sendMessage(["requestTelemetry": true], replyHandler: { [weak self] reply in
            guard let self else { return }
            if let data = reply["telemetry"] as? Data,
               let decoded = try? JSONDecoder().decode(LiveTelemetry.self, from: data) {
                DispatchQueue.main.async {
                    self.lastTelemetry = decoded
                    self.lastTelemetryReceivedAt = Date()
                    self.remoteState = decoded.guardState
                }
            }
        }, errorHandler: nil)
    }
#endif
    
    // MARK: - iPhone (receive + store)
    
    private func receiveAssistEvent(_ data: Data) {
        guard let event = try? JSONDecoder().decode(AssistEvent.self, from: data) else { return }
        
        assistEvents.append(event)
        // Keep last 100 events
        if assistEvents.count > 100 {
            assistEvents.removeFirst(assistEvents.count - 100)
        }
        saveEvents()
    }
    
    private func saveEvents() {
        if let encoded = try? JSONEncoder().encode(assistEvents) {
            UserDefaults.standard.set(encoded, forKey: eventsKey)
        }
    }
    
    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([AssistEvent].self, from: data) else { return }
        assistEvents = decoded
    }
    
    func clearEvents() {
        assistEvents.removeAll()
        UserDefaults.standard.removeObject(forKey: eventsKey)
    }

    // MARK: - Demo (iPhone-only)

#if os(iOS)
    /// Adds a small set of sample events so charts/timeline have something to render.
    func addDemoEvents() {
        let now = Date()
        let demo: [AssistEvent] = [
            AssistEvent(timestamp: now.addingTimeInterval(-60 * 12), type: "start"),
            AssistEvent(timestamp: now.addingTimeInterval(-60 * 9), type: "turn"),
            AssistEvent(timestamp: now.addingTimeInterval(-60 * 6), type: "start"),
            AssistEvent(timestamp: now.addingTimeInterval(-60 * 2), type: "turn")
        ]
        assistEvents.append(contentsOf: demo)
        assistEvents.sort { $0.timestamp > $1.timestamp }
        if assistEvents.count > 100 {
            assistEvents.removeFirst(assistEvents.count - 100)
        }
        saveEvents()
    }

    /// Simulates a live session: toggles state and emits assist events every few seconds.
    func startLiveDemo() {
        stopLiveDemo()
        remoteState = "monitoringStill"

        demoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Rotate through a believable pattern.
            let roll = Int.random(in: 0...9)
            switch roll {
            case 0...4:
                self.remoteState = "monitoringWalking"
            case 5:
                self.remoteState = "monitoringStill"
            case 6:
                self.remoteState = "cueingStartAssist"
                self.assistEvents.append(AssistEvent(timestamp: Date(), type: "start"))
            case 7:
                self.remoteState = "cueingTurnAssist"
                self.assistEvents.append(AssistEvent(timestamp: Date(), type: "turn"))
            default:
                self.remoteState = "cooldown"
            }

            // Keep the list bounded + persist so charts update reliably.
            self.assistEvents.sort { $0.timestamp > $1.timestamp }
            if self.assistEvents.count > 100 {
                self.assistEvents.removeFirst(self.assistEvents.count - 100)
            }
            self.saveEvents()
        }
        RunLoop.main.add(demoTimer!, forMode: .common)
    }

    func stopLiveDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
        remoteState = "off"
    }

    var isLiveDemoRunning: Bool { demoTimer != nil }
#endif
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.flushPendingStateIfNeeded()
#if os(iOS)
            self.hydrateFromApplicationContext()
#endif
        }
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Session inactive
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let data = message["assistEvent"] as? Data {
                self.receiveAssistEvent(data)
            }
            if let state = message["guardState"] as? String {
                self.remoteState = state
            }
            if let data = message["telemetry"] as? Data,
               let decoded = try? JSONDecoder().decode(LiveTelemetry.self, from: data) {
#if os(iOS)
                self.lastTelemetry = decoded
                self.lastTelemetryReceivedAt = Date()
                self.remoteState = decoded.guardState
#endif
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Some flows call this variant; forward to the same handler and ack.
        // iPhone can explicitly ask the watch for the latest state.
#if os(watchOS)
        if (message["requestState"] as? Bool) == true {
            replyHandler(["guardState": self.localState])
            return
        }
        if (message["requestTelemetry"] as? Bool) == true {
            if let data = session.receivedApplicationContext["telemetry"] as? Data {
                replyHandler(["telemetry": data])
            } else {
                replyHandler([:])
            }
            return
        }
#endif
        self.session(session, didReceiveMessage: message)
        replyHandler([:])
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let data = applicationContext["assistEvent"] as? Data {
                self.receiveAssistEvent(data)
            }
            if let state = applicationContext["guardState"] as? String {
                self.remoteState = state
            }
            if let data = applicationContext["telemetry"] as? Data,
               let decoded = try? JSONDecoder().decode(LiveTelemetry.self, from: data) {
#if os(iOS)
                self.lastTelemetry = decoded
                self.lastTelemetryReceivedAt = Date()
                self.remoteState = decoded.guardState
#endif
            }
        }
    }
}

