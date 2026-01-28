import Foundation
import CoreMotion
import WatchKit
import Combine

/// Motion + detection engine for gait initiation / turn-freeze cueing.
///
/// Notes:
/// - Uses device motion (`userAcceleration` + `rotationRate`) in `.xArbitraryZVertical` frame for a stable vertical axis.
/// - This is NOT a medical device. It is a cueing aid and should be tested supervised first.
final class MotionDetector: ObservableObject {
    enum GuardState: String {
        case off
        case monitoringStill
        case monitoringWalking
        case cueingStartAssist
        case cueingTurnAssist
        case cooldown
    }

    struct Settings: Equatable {
        /// 0.0 = less sensitive (fewer cues), 1.0 = more sensitive (more cues)
        var sensitivity: Double = 0.55
        /// Seconds after a cue where we will not cue again.
        var cooldownSeconds: Double = 10
        /// Seconds the metronome cue runs.
        var cueDurationSeconds: Double = 6
    }

    @Published private(set) var state: GuardState = .off
    @Published private(set) var isMonitoring: Bool = false
    @Published var settings: Settings = Settings()

    @Published private(set) var assistsToday: Int = 0
    @Published private(set) var lastAssistText: String = "—"

    private let motionManager = CMMotionManager()

    // Rolling sample history (simple + cheap).
    private var lastSamples: [(t: TimeInterval, userAccMag: Double, rotZ: Double, rotMag: Double)] = []
    private let maxWindowSeconds: TimeInterval = 2.2

    private var lastPeakTime: TimeInterval = 0
    private var peakTimes: [TimeInterval] = []

    private var lastAttemptStart: TimeInterval?
    private var lastTurnStart: TimeInterval?

    private var cueTimer: DispatchSourceTimer?
    private var cueEndTimer: DispatchSourceTimer?
    private var cooldownUntil: Date?

    private let defaults = UserDefaults.standard
    private let assistsDateKey = "gaitguard.assists.date"
    private let assistsCountKey = "gaitguard.assists.count"
    private let lastAssistAtKey = "gaitguard.assists.lastAt"

    init() {
        loadAssistStats()
    }
    
    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !isMonitoring else { return }

        // Reset transient detection state when (re)starting.
        lastSamples.removeAll(keepingCapacity: true)
        peakTimes.removeAll(keepingCapacity: true)
        lastPeakTime = 0
        lastAttemptStart = nil
        lastTurnStart = nil
        cooldownUntil = nil

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        isMonitoring = true
        state = .monitoringStill

        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest(motion: motion)
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        state = .off
        lastAttemptStart = nil
        lastTurnStart = nil
        lastSamples.removeAll(keepingCapacity: false)
        peakTimes.removeAll(keepingCapacity: false)
        stopCueTimers()
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Ingest + detection

    private func ingest(motion: CMDeviceMotion) {
        guard isMonitoring else { return }

        // Cooldown handling (state stays cooldown until expiry, then drops back to monitoring).
        if let until = cooldownUntil, Date() < until {
            state = .cooldown
        } else if state == .cooldown {
            cooldownUntil = nil
            state = .monitoringStill
        }

        let t = motion.timestamp
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z
        let userAccMag = sqrt(ax * ax + ay * ay + az * az)

        let rotX = motion.rotationRate.x
        let rotY = motion.rotationRate.y
        let rotZ = motion.rotationRate.z
        let rotMag = sqrt(rotX * rotX + rotY * rotY + rotZ * rotZ)

        lastSamples.append((t: t, userAccMag: userAccMag, rotZ: abs(rotZ), rotMag: rotMag))
        trimWindows(now: t)

        updateStepPeaks(now: t)
        let cadenceHz = stepCadenceHz(now: t)

        // High-level walking/still classification for UX + gating.
        if cadenceHz >= 0.85 {
            if !isCueing {
                state = .monitoringWalking
            }
        } else if !isCueing, state != .cooldown {
            state = .monitoringStill
        }

        // Don’t re-trigger while cueing / cooldown.
        guard !isCueing else { return }
        guard cooldownUntil == nil else { return }

        // 1) Initiation freeze assist:
        // If we detect an "attempt" after being still but do not see steps appear within a short window, cue.
        if shouldConsiderInitiationAttempt(userAccMag: userAccMag, rotMag: rotMag) {
            if lastAttemptStart == nil {
                lastAttemptStart = t
            }
        } else if let start = lastAttemptStart {
            // End the attempt if it fizzles quickly.
            if t - start > 1.0 && cadenceHz < 0.4 {
                lastAttemptStart = nil
            }
        }

        if let start = lastAttemptStart {
            let attemptAge = t - start
            // Require the "attempt" to persist a bit (avoid single sample spikes).
            if attemptAge >= 0.4 && attemptAge <= 2.2 && cadenceHz < initiationCadenceGateHz() {
                // If after ~1.3s we still don't see steps, cue.
                if attemptAge >= 1.3 {
                    lastAttemptStart = nil
                    triggerCue(type: .cueingStartAssist)
                    return
                }
            }
            // If they started walking, clear attempt.
            if cadenceHz >= 0.85 {
                lastAttemptStart = nil
            }
        }

        // 2) Turn-freeze assist:
        // Turning is high-risk; cue if there is sustained yaw rotation but cadence stays low.
        let turningNow = isTurningNow()
        if turningNow {
            if lastTurnStart == nil {
                lastTurnStart = t
            }
        } else {
            lastTurnStart = nil
        }

        if let turnStart = lastTurnStart {
            let turnAge = t - turnStart
            if turnAge >= 0.6 && cadenceHz < turnCadenceGateHz() {
                // Persisted turn-without-steps → cue.
                lastTurnStart = nil
                triggerCue(type: .cueingTurnAssist)
                return
            }
        }
    }

    private func trimWindows(now: TimeInterval) {
        let cutoff = now - maxWindowSeconds
        if !lastSamples.isEmpty {
            // Drop old samples.
            while let first = lastSamples.first, first.t < cutoff {
                lastSamples.removeFirst()
            }
        }
        // Trim peak history to same window.
        while let first = peakTimes.first, first < cutoff {
            peakTimes.removeFirst()
        }
    }

    private func shouldConsiderInitiationAttempt(userAccMag: Double, rotMag: Double) -> Bool {
        // A small movement that suggests an intent to start, not a big shake.
        return userAccMag > attemptAccThreshold() || rotMag > attemptRotThreshold()
    }

    private func isTurningNow() -> Bool {
        // Look at last ~0.4s for sustained yaw (rotZ).
        guard let newest = lastSamples.last else { return false }
        let cutoff = newest.t - 0.45
        let recent = lastSamples.filter { $0.t >= cutoff }
        guard recent.count >= 8 else { return false } // ~0.16s at 50Hz minimum

        let above = recent.filter { $0.rotZ >= turnYawThresholdRadPerSec() }.count
        // Require most of that short window to be above threshold.
        return Double(above) / Double(recent.count) >= 0.70
    }

    // MARK: - Step peaks (cheap cadence proxy)

    private func updateStepPeaks(now: TimeInterval) {
        // Need at least 3 samples to detect a local max.
        guard lastSamples.count >= 3 else { return }
        let n = lastSamples.count
        let a0 = lastSamples[n - 3].userAccMag
        let a1 = lastSamples[n - 2].userAccMag
        let a2 = lastSamples[n - 1].userAccMag

        // Local max + amplitude threshold.
        guard a1 > a0, a1 > a2, a1 >= stepPeakThreshold() else { return }

        // Enforce minimum spacing between peaks (avoid double-counting).
        let minSpacing = 0.28
        guard (now - lastPeakTime) >= minSpacing else { return }

        lastPeakTime = now
        peakTimes.append(now)
    }

    private func stepCadenceHz(now: TimeInterval) -> Double {
        // Peaks in last 2 seconds → Hz estimate.
        let window: TimeInterval = 2.0
        let cutoff = now - window
        let recentPeaks = peakTimes.filter { $0 >= cutoff }
        return Double(recentPeaks.count) / window
    }

    // MARK: - Thresholds (tunable)

    private func attemptAccThreshold() -> Double {
        // More sensitive => lower threshold.
        return 0.16 - (0.06 * settings.sensitivity) // ~0.10–0.16 g
    }

    private func attemptRotThreshold() -> Double {
        // More sensitive => lower threshold.
        return 1.2 - (0.5 * settings.sensitivity) // ~0.7–1.2 rad/s
    }

    private func stepPeakThreshold() -> Double {
        // More sensitive => lower threshold.
        return 0.22 - (0.10 * settings.sensitivity) // ~0.12–0.22 g
    }

    private func turnYawThresholdRadPerSec() -> Double {
        // More sensitive => lower threshold.
        return 1.35 - (0.55 * settings.sensitivity) // ~0.8–1.35 rad/s
    }

    private func initiationCadenceGateHz() -> Double {
        // If we don't see at least this cadence during an attempt, we consider it "stuck".
        return 0.55 + (0.10 * (1.0 - settings.sensitivity)) // ~0.55–0.65 Hz
    }

    private func turnCadenceGateHz() -> Double {
        return 0.75 + (0.10 * (1.0 - settings.sensitivity)) // ~0.75–0.85 Hz
    }

    // MARK: - Cueing

    private var isCueing: Bool {
        state == .cueingStartAssist || state == .cueingTurnAssist
    }

    private func triggerCue(type: GuardState) {
        guard type == .cueingStartAssist || type == .cueingTurnAssist else { return }
        guard isMonitoring else { return }

        // Enter cueing state.
        state = type
        recordAssist()

        // Configure cue cadence:
        // - Start assist: faster rhythm to help initiate stepping
        // - Turn assist: slightly slower to encourage controlled, staged turns
        let interval: TimeInterval = (type == .cueingStartAssist) ? 0.48 : 0.62

        stopCueTimers()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler {
            // Stronger haptic for real-world cueing.
            WKInterfaceDevice.current().play(.directionUp)
        }
        timer.resume()
        cueTimer = timer

        let endTimer = DispatchSource.makeTimerSource(queue: .main)
        endTimer.schedule(deadline: .now() + settings.cueDurationSeconds)
        endTimer.setEventHandler { [weak self] in
            self?.endCue()
        }
        endTimer.resume()
        cueEndTimer = endTimer
    }

    private func endCue() {
        stopCueTimers()
        cooldownUntil = Date().addingTimeInterval(settings.cooldownSeconds)
        state = .cooldown
    }

    private func stopCueTimers() {
        cueTimer?.cancel()
        cueTimer = nil
        cueEndTimer?.cancel()
        cueEndTimer = nil
    }

    // MARK: - Assist stats

    private func loadAssistStats() {
        let today = Calendar.current.startOfDay(for: Date())
        let storedDay = defaults.object(forKey: assistsDateKey) as? Date

        if let storedDay, Calendar.current.isDate(storedDay, inSameDayAs: today) {
            assistsToday = defaults.integer(forKey: assistsCountKey)
        } else {
            defaults.set(today, forKey: assistsDateKey)
            defaults.set(0, forKey: assistsCountKey)
            assistsToday = 0
        }

        if let lastAt = defaults.object(forKey: lastAssistAtKey) as? Date {
            lastAssistText = Self.formatTime(lastAt)
        } else {
            lastAssistText = "—"
        }
    }

    private func recordAssist() {
        // Reset daily counter if needed.
        let today = Calendar.current.startOfDay(for: Date())
        let storedDay = defaults.object(forKey: assistsDateKey) as? Date
        if storedDay == nil || !Calendar.current.isDate(storedDay!, inSameDayAs: today) {
            defaults.set(today, forKey: assistsDateKey)
            defaults.set(0, forKey: assistsCountKey)
            assistsToday = 0
        }

        assistsToday += 1
        defaults.set(assistsToday, forKey: assistsCountKey)

        let now = Date()
        defaults.set(now, forKey: lastAssistAtKey)
        lastAssistText = Self.formatTime(now)
        
        // Send to iPhone via WatchConnectivity
        let assistType = (state == .cueingStartAssist) ? "start" : "turn"
        WatchConnectivityManager.shared.sendAssistEvent(type: assistType)
    }

    // MARK: - Manual testing helpers (for development / demo)

    enum AssistKind {
        case start
        case turn
    }

    func testHaptic() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    /// Simulate an assist event (updates stats + sends to iPhone) so you can verify UI + connectivity.
    func simulateAssist(kind: AssistKind) {
        state = (kind == .start) ? .cueingStartAssist : .cueingTurnAssist
        recordAssist()
        WKInterfaceDevice.current().play(.directionUp)
    }

    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}
