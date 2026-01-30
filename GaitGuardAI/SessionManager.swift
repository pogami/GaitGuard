// SessionManager.swift
import Foundation
import WatchKit
import Combine

final class SessionManager: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    @Published var isSessionActive = false

    private var session: WKExtendedRuntimeSession?

    func startSession() {
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        isSessionActive = true
    }

    func stopSession() {
        session?.invalidate()
        session = nil
        isSessionActive = false
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        isSessionActive = true
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        isSessionActive = false
        // Session expiring often indicates low battery or system resource constraints
        // Trigger haptic alert
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        isSessionActive = false
    }
}
