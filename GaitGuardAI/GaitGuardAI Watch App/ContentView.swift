import SwiftUI

struct ContentView: View {
    @StateObject private var engine = MotionDetector()
    @StateObject private var gaitTrackingManager: GaitTrackingManager
    // 1. Reference the SessionManager from the environment
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isActive = false
    
    init() {
        let detector = MotionDetector()
        _engine = StateObject(wrappedValue: detector)
        _gaitTrackingManager = StateObject(wrappedValue: GaitTrackingManager(motionDetector: detector))
    }
    
    var body: some View {
        Group {
            if engine.isCalibrating {
                // Calibration Mode UI - Full Screen
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 30))
                            .foregroundColor(.orange)
                            .symbolEffect(.pulse)
                        
                        Text("Calibrating...")
                            .font(.system(.caption, design: .rounded).bold())
                        
                        // Countdown Timer
                        Text("\(engine.calibrationTimeRemaining)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        
                        Text("seconds")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        // Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 8)
                                    .cornerRadius(4)
                                
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: geometry.size.width * engine.calibrationProgress, height: 8)
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal, 20)
                        
                        Text("Walk normally")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        Button("Cancel") {
                            engine.stopCalibration()
                        }
                        .tint(.red)
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Normal Monitoring UI
                ScrollView {
                    VStack(spacing: 8) {
                        // Large Status Icon
                        Image(systemName: isActive ? "bolt.shield.fill" : "shield.slash")
                            .font(.system(size: 35))
                            .foregroundColor(isActive ? .green : .gray)
                            .symbolEffect(.pulse, isActive: isActive)
                        
                        Text(isActive ? "Monitoring Gait" : "Guard is Off")
                            .font(.system(.caption, design: .rounded).bold())
                        
                        // Connection hint when not active
                        if !isActive {
                            Text("Open iPhone app to sync data")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        
                        // Battery warning
                        if engine.monitoringStoppedDueToBattery {
                            Text("Battery Low - Monitoring Stopped")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                        
                // Show calibration status if available
                if engine.hasCalibrationData() {
                    Text("Calibrated")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 4)
                } else if engine.isCalibrationUnstable() {
                            VStack(spacing: 4) {
                                Text("Calibration Unstable")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Text("Please try again")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        
                        // Buttons
                        // The Start/Stop Button
                        Button(action: {
                            isActive.toggle()
                            if isActive {
                                // 2. Trigger the Background Session FIRST
                                sessionManager.startSession()
                                // Start GaitTrackingManager for background persistence
                                gaitTrackingManager.startTracking()
                                // Then start your 50Hz logic
                                engine.startMonitoring()
                            } else {
                                // Stop tracking
                                gaitTrackingManager.stopTracking()
                                // 3. Optional: Add a stopSession() to your manager if you want to save battery
                                engine.stopMonitoring()
                            }
                        }) {
                            Text(isActive ? "STOP" : "START")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(isActive ? .red : .blue)
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        
                        // Calibration Button - Compact version
                        Button(action: {
                            engine.startCalibration()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "gauge")
                                    .font(.caption2)
                                Text("Calibrate")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .tint(.orange)
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        // Using the gradient background you liked
        .containerBackground(
            engine.isCalibrating ? Color.orange.gradient :
            (isActive ? Color.green.gradient : Color.blue.gradient),
            for: .navigation
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetToFactorySettings"))) { _ in
            engine.resetToFactorySettings()
        }
    }
}
