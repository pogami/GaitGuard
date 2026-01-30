import SwiftUI
import WatchConnectivity

struct RemoteControlsView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var hapticIntensity: Double
    @State private var sensitivity: Double
    @State private var adaptiveThreshold: Bool
    @State private var hapticPattern: String
    @State private var repeatHaptics: Bool
    @State private var showTestSuccess = false
    @State private var showTestError = false
    @State private var showResetConfirmation = false
    @State private var showResetSuccess = false
    @State private var testLatency: TimeInterval = 0.0
    
    init() {
        let settings = WatchConnectivityManager.shared.watchSettings
        _hapticIntensity = State(initialValue: settings.hapticIntensity)
        _sensitivity = State(initialValue: settings.sensitivity)
        _adaptiveThreshold = State(initialValue: settings.adaptiveThreshold)
        _hapticPattern = State(initialValue: settings.hapticPattern)
        _repeatHaptics = State(initialValue: settings.repeatHaptics)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Haptic Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Intensity")
                            Spacer()
                            Text("\(Int(hapticIntensity * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $hapticIntensity, in: 0.0...1.0, step: 0.1)
                            .onChange(of: hapticIntensity) { oldValue, newValue in
                                updateSettings()
                            }
                    }
                    
                    Picker("Pattern", selection: $hapticPattern) {
                        Text("Direction Up").tag("directionUp")
                        Text("Notification").tag("notification")
                        Text("Start").tag("start")
                        Text("Stop").tag("stop")
                        Text("Click").tag("click")
                    }
                    .onChange(of: hapticPattern) { oldValue, newValue in
                        updateSettings()
                    }
                    
                    Toggle("Repeat Haptics", isOn: $repeatHaptics)
                        .onChange(of: repeatHaptics) { oldValue, newValue in
                            updateSettings()
                        }
                }
                
                Section("Detection Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text(String(format: "%.2f", sensitivity))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $sensitivity, in: 0.5...3.0, step: 0.1)
                            .onChange(of: sensitivity) { oldValue, newValue in
                                updateSettings()
                            }
                        Text("Lower = more sensitive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Adaptive Threshold", isOn: $adaptiveThreshold)
                        .onChange(of: adaptiveThreshold) { oldValue, newValue in
                            updateSettings()
                        }
                    
                    if adaptiveThreshold {
                        Text("Automatically adjusts based on your normal gait pattern")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Test") {
                    Button("Test Trigger") {
                        testHaptic()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!connectivityManager.isWatchReachable)
                    
                    if showTestSuccess {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Haptic sent to watch!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            if testLatency > 0 {
                                Text("Response time: \(String(format: "%.0f", testLatency * 1000))ms")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .transition(.opacity)
                    }
                    
                    if showTestError {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Watch not connected")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .transition(.opacity)
                    }
                    
                    if !connectivityManager.isWatchReachable {
                        VStack(alignment: .leading, spacing: 4) {
                            if connectivityManager.activationState == .notActivated {
                                Text("Initializing connection...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else if connectivityManager.isWatchConnected {
                                if let startTime = connectivityManager.sessionStartTime {
                                    let elapsed = Date().timeIntervalSince(startTime)
                                    if elapsed < 60 && connectivityManager.sessionActivated {
                                        Text("Waiting for watch app to become reachable...")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text("This can take up to 60 seconds after launch")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Watch app must be running on your watch")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    Text("Watch app must be running on your watch")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Text("Connect your watch to test")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            #if targetEnvironment(simulator)
                            Text("⚠️ Simulator detected - WatchConnectivity requires physical devices")
                                .font(.caption2)
                                .foregroundColor(.red)
                            #endif
                        }
                    }
                }
                
                Section("Calibration") {
                    Button("Reset to Factory Settings") {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.red)
                    
                    if showResetSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Reset to factory settings")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .transition(.opacity)
                    }
                }
                .alert("Reset to Factory Settings", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        resetToFactory()
                    }
                } message: {
                    Text("This will reset all calibration data and settings to default values. This cannot be undone.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not a Medical Device")
                            .font(.headline)
                        Text("GaitGuardAI is a wellness and activity monitoring tool. It is not intended to diagnose, treat, cure, or prevent any disease or medical condition. Always consult with healthcare professionals for medical advice.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Disclaimer")
                }
            }
            .navigationTitle("Remote Controls")
        }
    }
    
    private func updateSettings() {
        var newSettings = connectivityManager.watchSettings
        newSettings.hapticIntensity = hapticIntensity
        newSettings.sensitivity = sensitivity
        newSettings.adaptiveThreshold = adaptiveThreshold
        newSettings.hapticPattern = hapticPattern
        newSettings.repeatHaptics = repeatHaptics
        
        connectivityManager.updateSettings(newSettings)
    }
    
    private func testHaptic() {
        // Check if watch is actually reachable
        connectivityManager.updateConnectionStatus()
        
        if connectivityManager.isWatchReachable {
            connectivityManager.testHaptic()
            
            // Calculate latency (approximate, since we don't get reply)
            // We'll use heartbeat latency if available, otherwise estimate
            let estimatedLatency = connectivityManager.heartbeatLatency > 0 ? 
                connectivityManager.heartbeatLatency : 0.1
            
            testLatency = estimatedLatency
            
            // Show success feedback
            withAnimation {
                showTestSuccess = true
                showTestError = false
            }
            
            #if DEBUG
            print("[GaitGuard] iPhone → Test haptic sent (estimated latency: \(String(format: "%.0f", estimatedLatency * 1000))ms)")
            #endif
            
            // Hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showTestSuccess = false
                    testLatency = 0.0
                }
            }
        } else {
            // Show error feedback
            withAnimation {
                showTestError = true
                showTestSuccess = false
            }
            
            #if DEBUG
            print("[GaitGuard] iPhone → Test haptic failed (watch not reachable)")
            #endif
            
            // Hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showTestError = false
                }
            }
        }
    }
    
    private func resetToFactory() {
        // Reset local settings
        var factorySettings = WatchSettings()
        factorySettings.sensitivity = 1.3
        factorySettings.adaptiveThreshold = false
        connectivityManager.updateSettings(factorySettings)
        
        // Send reset command to watch
        connectivityManager.resetToFactorySettings()
        
        // Show success feedback
        withAnimation {
            showResetSuccess = true
        }
        
        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showResetSuccess = false
            }
        }
    }
}
