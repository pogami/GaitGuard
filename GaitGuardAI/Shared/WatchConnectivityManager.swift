// WatchConnectivityManager.swift
// Shared between watch + iPhone to sync assist events.
import Foundation
import WatchConnectivity
import Combine

struct AssistEvent: Codable {
    let timestamp: Date
    let type: String // "start" or "turn"
}

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var assistEvents: [AssistEvent] = []
    
    private let session: WCSession?
    private let eventsKey = "gaitguard.assistEvents"
    
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
    }
    
    // MARK: - Watch → iPhone (send from watch)
    
    func sendAssistEvent(type: String) {
        guard let session = session, session.isPaired else { return }
        
        let event = AssistEvent(timestamp: Date(), type: type)
        guard let data = try? JSONEncoder().encode(event) else { return }
        
        if session.isReachable {
            session.sendMessage(["assistEvent": data], replyHandler: nil)
        } else {
            // Fallback: update application context (works when iPhone app is backgrounded)
            try? session.updateApplicationContext(["assistEvent": data])
        }
    }
    
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
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Session activated
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
        if let data = message["assistEvent"] as? Data {
            receiveAssistEvent(data)
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["assistEvent"] as? Data {
            receiveAssistEvent(data)
        }
    }
}

