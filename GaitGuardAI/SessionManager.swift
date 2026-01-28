// SessionManager.swift
import Foundation
import WatchKit
import Combine

final class SessionManager: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    @Published var isSessionActive = false

    private var session: WKExtendedRuntimeSession?

    func startSession() {
        // Avoid starting multiple sessions.
        guard session == nil else {
            isSessionActive = true
            return
        }
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
    }

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        isSessionActive = false
    }
}
