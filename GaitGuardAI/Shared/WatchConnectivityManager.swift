// WatchConnectivityManager.swift
// Shared between watch + iPhone to sync assist events.
import Foundation
import WatchConnectivity
import Combine
#if os(watchOS)
import WatchKit
#endif

struct AssistEvent: Codable {
    let timestamp: Date
    let type: String // "start" or "turn"
    let severity: Double // 0.0 to 1.0, magnitude normalized
    let duration: TimeInterval? // Optional: how long the freeze lasted
}

// Live accelerometer data point
struct AccelerometerData: Codable {
    let x: Double
    let y: Double
    let z: Double
    let timestamp: Date
}

// Calibration results
struct CalibrationResults: Codable {
    let average: Double
    let standardDeviation: Double
    let baselineThreshold: Double
    let sampleCount: Int
    let timestamp: Date
}

// Settings that can be controlled from iPhone
struct WatchSettings: Codable {
    var hapticIntensity: Double = 1.0 // 0.0 to 1.0
    var sensitivity: Double = 1.3 // Motion threshold
    var adaptiveThreshold: Bool = true
    var hapticPattern: String = "directionUp" // "directionUp", "notification", "start", "stop"
    var repeatHaptics: Bool = false
}

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var assistEvents: [AssistEvent] = []
    @Published var isWatchConnected = false
    @Published var isWatchReachable = false
    @Published var lastEventTime: Date?
    @Published var watchSessionActive = false
    @Published var watchSettings = WatchSettings()
    @Published var isWatchCalibrating = false
    @Published var calibrationProgress: Double = 0.0
    @Published var calibrationTimeRemaining: Int = 30
    @Published var lastHeartbeatTime: Date?
    @Published var heartbeatLatency: TimeInterval = 0.0 // Time taken for heartbeat round-trip
    @Published var sessionActivated = false
    @Published var activationState: WCSessionActivationState = .notActivated
    @Published var sessionStartTime: Date? // Track when session activation started
    @Published var liveAccelerometerData: [AccelerometerData] = [] // Live data for Analytics view
    @Published var lastCalibrationResults: CalibrationResults? // Latest calibration results
    
    private let session: WCSession?
    private var heartbeatTimer: Timer?
    var wcSession: WCSession? { session } // Public accessor for session
    private let eventsKey = "gaitguard.assistEvents"
    private let settingsKey = "gaitguard.watchSettings"
    private var pendingEvents: [AssistEvent] = [] // Queue for offline sync
    private let maxLiveDataPoints = 500 // Keep last 500 data points for visualization
    
    override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
        
        session?.delegate = self
        session?.activate()
        sessionStartTime = Date() // Track when we started activation
        
        loadEvents()
        loadSettings()
        updateConnectionStatus()
        syncPendingEvents()
        
        #if DEBUG
        print("[GaitGuard] WatchConnectivityManager initialized")
        #endif
    }
    
    deinit {
        stopHeartbeat()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            watchSettings = decoded
        }
    }
    
    func updateSettings(_ newSettings: WatchSettings) {
        watchSettings = newSettings
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
        sendSettingsToWatch()
    }
    
    private     func sendSettingsToWatch() {
        guard let session = session, session.activationState == .activated else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot send settings: WCSession not activated")
            #endif
            return
        }
        guard session.isReachable else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot send settings: Watch not reachable")
            #endif
            return
        }
        if let data = try? JSONEncoder().encode(watchSettings) {
            session.sendMessage(["watchSettings": data], replyHandler: nil)
        }
    }
    
    // MARK: - Connection Status
    
    func updateConnectionStatus() {
        guard let session = session else {
            DispatchQueue.main.async { [weak self] in
                self?.isWatchConnected = false
                self?.isWatchReachable = false
                self?.watchSessionActive = false
                self?.sessionActivated = false
            }
            return
        }
        
        // Check if session is activated
        let currentActivationState = session.activationState
        let isActivated = currentActivationState == .activated
        
        let isPaired: Bool
        let isReachable: Bool
        
        #if os(watchOS)
        isPaired = true
        isReachable = isActivated && session.isReachable
        #else
        isPaired = isActivated && session.isPaired
        isReachable = isActivated && session.isReachable
        
        // Check for simulator/device mismatch
        #if targetEnvironment(simulator)
        if isActivated && !session.isPaired {
            #if DEBUG
            print("[GaitGuard] ⚠️ Running on Simulator - WatchConnectivity requires both apps on physical devices")
            #endif
        }
        #endif
        #endif
        
        // Update on main thread for UI
        DispatchQueue.main.async { [weak self] in
            self?.activationState = currentActivationState
            self?.sessionActivated = isActivated
            self?.isWatchConnected = isPaired
            self?.isWatchReachable = isReachable
            self?.watchSessionActive = isActivated
            
            #if DEBUG
            if !isActivated {
                switch currentActivationState {
                case .notActivated:
                    print("[GaitGuard] ⚠️ WCSession not activated yet (still initializing)")
                case .inactive:
                    print("[GaitGuard] ⚠️ WCSession is inactive")
                case .activated:
                    // Shouldn't reach here, but included for exhaustiveness
                    break
                @unknown default:
                    print("[GaitGuard] ⚠️ WCSession in unknown state")
                }
            }
            
            #if !os(watchOS)
            if isActivated && !session.isPaired {
                print("[GaitGuard] ⚠️ iPhone: Watch app not installed on paired watch")
            }
            #else
            if isActivated && !session.isReachable {
                print("[GaitGuard] ⚠️ Watch: iPhone app not installed or not reachable")
            }
            #endif
            #endif
        }
    }
    
    // MARK: - Watch → iPhone (send from watch)
    
    func sendAssistEvent(type: String, severity: Double = 0.5, duration: TimeInterval? = nil) {
        guard let session = session, session.activationState == .activated else {
            // Queue for later if no session or not activated
            let event = AssistEvent(timestamp: Date(), type: type, severity: severity, duration: duration)
            pendingEvents.append(event)
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot send event: WCSession not activated - queued for later")
            #endif
            return
        }
        
        let event = AssistEvent(timestamp: Date(), type: type, severity: severity, duration: duration)
        
        #if DEBUG
        #if os(watchOS)
        print("[GaitGuard] Watch → Assist event sent: \(type) (severity: \(String(format: "%.2f", severity)))")
        #endif
        #endif
        
        guard let data = try? JSONEncoder().encode(event) else { return }
        
        #if os(watchOS)
        if session.isReachable {
            session.sendMessage(["assistEvent": data], replyHandler: nil)
        } else {
            // Queue for later sync
            pendingEvents.append(event)
            // Fallback: update application context
            try? session.updateApplicationContext(["assistEvent": data])
        }
        #else
        if session.isReachable || session.isPaired {
            if session.isReachable {
                session.sendMessage(["assistEvent": data], replyHandler: nil)
            } else {
                try? session.updateApplicationContext(["assistEvent": data])
            }
        }
        #endif
    }
    
    private func syncPendingEvents() {
        guard let session = session, session.isReachable, !pendingEvents.isEmpty else { return }
        
        for event in pendingEvents {
            if let data = try? JSONEncoder().encode(event) {
                session.sendMessage(["assistEvent": data], replyHandler: nil)
            }
        }
        pendingEvents.removeAll()
    }
    
    // MARK: - iPhone (receive + store)
    
    private func receiveAssistEvent(_ data: Data) {
        guard let event = try? JSONDecoder().decode(AssistEvent.self, from: data) else { return }
        
        #if DEBUG
        #if !os(watchOS)
        print("[GaitGuard] iPhone → Assist event received: \(event.type) at \(event.timestamp)")
        #endif
        #endif
        
        // Update on main thread for real-time UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.assistEvents.append(event)
            self.lastEventTime = event.timestamp
            
            // Keep last 100 events
            if self.assistEvents.count > 100 {
                self.assistEvents.removeFirst(self.assistEvents.count - 100)
            }
            self.saveEvents()
        }
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
    
    // MARK: - Live Accelerometer Data Streaming
    
    #if os(watchOS)
    func sendAccelerometerData(x: Double, y: Double, z: Double, timestamp: Date) {
        guard let session = session, session.activationState == .activated else { return }
        
        let data = AccelerometerData(x: x, y: y, z: z, timestamp: timestamp)
        
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        
        if session.isReachable {
            session.sendMessage(["accelerometerData": encoded], replyHandler: nil)
        } else {
            // Queue for later if not reachable
            // Note: For live streaming, we might want to drop old data if queue gets too large
        }
    }
    #endif
    
    func sendCalibrationResults(average: Double, standardDeviation: Double, baselineThreshold: Double, sampleCount: Int) {
        #if os(watchOS)
        guard let session = session, session.activationState == .activated else { return }
        
        let results = CalibrationResults(
            average: average,
            standardDeviation: standardDeviation,
            baselineThreshold: baselineThreshold,
            sampleCount: sampleCount,
            timestamp: Date()
        )
        
        guard let encoded = try? JSONEncoder().encode(results) else { return }
        
        if session.isReachable {
            session.sendMessage(["calibrationResults": encoded], replyHandler: nil)
        } else {
            // Try application context as fallback
            try? session.updateApplicationContext(["calibrationResults": encoded])
        }
        
        #if DEBUG
        print("[GaitGuard] Watch → Calibration results sent: avg=\(String(format: "%.3f", average)), stdDev=\(String(format: "%.3f", standardDeviation)), threshold=\(String(format: "%.3f", baselineThreshold))")
        #endif
        #endif
    }
    
    // MARK: - Test Haptic
    
    func testHaptic() {
        // Update connection status first
        updateConnectionStatus()
        
        guard let session = session else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot test haptic: WCSession not available")
            #endif
            return
        }
        
        // Check if session is activated
        guard session.activationState == .activated else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot test haptic: WCSession not activated")
            #endif
            return
        }
        
        // Check if actually reachable
        guard session.isReachable else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot test haptic: Watch not reachable")
            #endif
            return
        }
        
        // Send test haptic with reply handler to confirm it was received
        session.sendMessage(
            ["testHaptic": true],
            replyHandler: { reply in
                // Watch confirmed receipt
                #if DEBUG
                print("[GaitGuard] ✅ Test haptic confirmed by watch")
                #endif
            }
        )
    }
    
    // MARK: - Factory Reset
    
    func resetToFactorySettings() {
        guard let session = session, session.activationState == .activated else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot reset: WCSession not activated")
            #endif
            return
        }
        guard session.isReachable else {
            #if DEBUG
            print("[GaitGuard] ⚠️ Cannot reset: Watch not reachable")
            #endif
            return
        }
        session.sendMessage(["resetToFactory": true], replyHandler: nil)
        
        #if DEBUG
        print("[GaitGuard] Reset to factory settings sent to watch")
        #endif
    }
    
    // MARK: - Heartbeat System
    
    func startHeartbeat() {
        stopHeartbeat() // Stop any existing heartbeat
        
        #if os(watchOS)
        // Watch sends heartbeat to iPhone
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        #else
        // iPhone receives heartbeat and responds
        // Heartbeat is started when monitoring starts on watch
        #endif
        
        #if DEBUG
        print("[GaitGuard] Heartbeat started")
        #endif
    }
    
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        #if os(watchOS)
        guard let session = session, session.activationState == .activated else {
            #if DEBUG
            print("[GaitGuard] Watch → Heartbeat skipped (session not activated)")
            #endif
            return
        }
        guard session.isReachable else {
            #if DEBUG
            print("[GaitGuard] Watch → Heartbeat skipped (not reachable)")
            #endif
            return
        }
        
        let timestamp = Date()
        let heartbeatData: [String: Any] = [
            "type": "heartbeat",
            "timestamp": timestamp.timeIntervalSince1970
        ]
        
        session.sendMessage(heartbeatData, replyHandler: { [weak self] reply in
            // iPhone confirmed receipt
            let latency = Date().timeIntervalSince(timestamp)
            DispatchQueue.main.async {
                self?.heartbeatLatency = latency
            }
            #if DEBUG
            print("[GaitGuard] Watch → Heartbeat confirmed (latency: \(String(format: "%.3f", latency))s)")
            #endif
        })
        
        #if DEBUG
        print("[GaitGuard] Watch → Heartbeat sent")
        #endif
        #endif
    }
    
    #if os(watchOS)
    private func getMotionDetector() -> MotionDetector? {
        // This is a helper to access MotionDetector from WatchConnectivityManager
        // In practice, you'd pass a reference or use a different pattern
        // For now, we'll use the direct haptic method
        return nil
    }
    #endif
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                #if DEBUG
                print("[GaitGuard] ❌ WCSession activation failed: \(error.localizedDescription)")
                #endif
            } else {
                switch activationState {
                case .activated:
                    if let startTime = self?.sessionStartTime {
                        let activationTime = Date().timeIntervalSince(startTime)
                        #if DEBUG
                        print("[GaitGuard] ✅ WCSession activated successfully (took \(String(format: "%.1f", activationTime))s)")
                        #endif
                    } else {
                        #if DEBUG
                        print("[GaitGuard] ✅ WCSession activated successfully")
                        #endif
                    }
                    // Note: Even after activation, isReachable may take up to 60 seconds
                    // This is normal WatchConnectivity behavior
                case .notActivated:
                    #if DEBUG
                    print("[GaitGuard] ⚠️ WCSession not activated - still initializing")
                    #endif
                case .inactive:
                    #if DEBUG
                    print("[GaitGuard] ⚠️ WCSession is inactive")
                    #endif
                @unknown default:
                    #if DEBUG
                    print("[GaitGuard] ⚠️ WCSession in unknown state")
                    #endif
                }
            }
            self?.activationState = activationState
            self?.updateConnectionStatus()
        }
    }
    
    #if !os(watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Session inactive
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle heartbeat
        if message["type"] as? String == "heartbeat" {
            #if !os(watchOS)
            // iPhone received heartbeat
            DispatchQueue.main.async { [weak self] in
                self?.lastHeartbeatTime = Date()
            }
            
            // Send reply to confirm receipt
            session.sendMessage(["heartbeatReply": true], replyHandler: nil)
            
            #if DEBUG
            print("[GaitGuard] iPhone → Heartbeat received")
            #endif
            #endif
            return
        }
        
        if let data = message["assistEvent"] as? Data {
            #if DEBUG
            print("[GaitGuard] iPhone → Assist event received")
            #endif
            receiveAssistEvent(data)
        }
        
        // Handle settings updates from iPhone
        if let data = message["watchSettings"] as? Data,
           let settings = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.watchSettings = settings
            }
            #if DEBUG
            print("[GaitGuard] Watch → Settings updated")
            #endif
        }
        
        // Handle calibration status from watch
        #if !os(watchOS)
        if let data = message["calibrationStatus"] as? Data {
            struct CalibrationStatus: Codable {
                let isCalibrating: Bool
                let progress: Double
                let timeRemaining: Int
            }
            
            if let status = try? JSONDecoder().decode(CalibrationStatus.self, from: data) {
                DispatchQueue.main.async { [weak self] in
                    self?.isWatchCalibrating = status.isCalibrating
                    self?.calibrationProgress = status.progress
                    self?.calibrationTimeRemaining = status.timeRemaining
                }
            }
        }
        
        // Handle calibration results from watch
        if let data = message["calibrationResults"] as? Data,
           let results = try? JSONDecoder().decode(CalibrationResults.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.lastCalibrationResults = results
            }
            #if DEBUG
            print("[GaitGuard] iPhone → Calibration results received: avg=\(String(format: "%.3f", results.average)), threshold=\(String(format: "%.3f", results.baselineThreshold))")
            #endif
        }
        
        // Handle live accelerometer data from watch
        if let data = message["accelerometerData"] as? Data,
           let accelData = try? JSONDecoder().decode(AccelerometerData.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.liveAccelerometerData.append(accelData)
                
                // Keep only last N data points to prevent memory issues
                if self.liveAccelerometerData.count > self.maxLiveDataPoints {
                    self.liveAccelerometerData.removeFirst(self.liveAccelerometerData.count - self.maxLiveDataPoints)
                }
            }
        }
        #endif
        
        // Handle test haptic request
        #if os(watchOS)
        if message["testHaptic"] != nil {
            let startTime = Date()
            let device = WKInterfaceDevice.current()
            let hapticType: WKHapticType
            switch watchSettings.hapticPattern {
            case "notification":
                hapticType = .notification
            case "start":
                hapticType = .start
            case "stop":
                hapticType = .stop
            case "click":
                hapticType = .click
            default:
                hapticType = .directionUp
            }
            device.play(hapticType)
            
            #if DEBUG
            let latency = Date().timeIntervalSince(startTime)
            print("[GaitGuard] Watch → Test haptic triggered (latency: \(String(format: "%.3f", latency))s)")
            #endif
        }
        
        // Handle factory reset request
        if message["resetToFactory"] != nil {
            NotificationCenter.default.post(name: NSNotification.Name("ResetToFactorySettings"), object: nil)
            #if DEBUG
            print("[GaitGuard] Watch → Factory reset received")
            #endif
        }
        #endif
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["assistEvent"] as? Data {
            receiveAssistEvent(data)
        }
        
        // Handle settings from application context
        if let data = applicationContext["watchSettings"] as? Data,
           let settings = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.watchSettings = settings
            }
        }
    }
    
    #if !os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.updateConnectionStatus()
        }
    }
    #endif
}

