import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var timer: Timer?
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            EventsListView()
                .tabItem {
                    Label("Events", systemImage: "list.bullet")
                }
                .tag(0)
            
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(1)
            
            RemoteControlsView()
                .tabItem {
                    Label("Controls", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
    }
}

struct EventsListView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            List {
                // Connection Status Section
                Section {
                    HStack {
                        Image(systemName: connectivityManager.isWatchReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectivityManager.isWatchReachable ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(connectivityManager.isWatchReachable ? "Watch Connected" : "Watch Disconnected")
                                    .font(.headline)
                                Button(action: {
                                    connectivityManager.updateConnectionStatus()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Heartbeat indicator
                            if connectivityManager.isWatchReachable, let lastHeartbeat = connectivityManager.lastHeartbeatTime {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                                                .scaleEffect(1.5)
                                                .opacity(1.0)
                                                .animation(
                                                    Animation.easeInOut(duration: 1.0)
                                                        .repeatForever(autoreverses: true),
                                                    value: connectivityManager.lastHeartbeatTime
                                                )
                                        )
                                    Text("Last updated: \(lastHeartbeat, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if connectivityManager.heartbeatLatency > 0 {
                                        Text("(\(String(format: "%.0f", connectivityManager.heartbeatLatency * 1000))ms)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            
                            // Show calibration status if active
                            if connectivityManager.isWatchCalibrating {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform.path")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Calibrating... \(connectivityManager.calibrationTimeRemaining)s")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(.top, 2)
                            } else if let lastEvent = connectivityManager.lastEventTime {
                                Text("Last event: \(lastEvent, style: .relative)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                if !connectivityManager.isWatchConnected {
                                    if connectivityManager.activationState == .notActivated {
                                        Text("Initializing connection...")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    } else {
                                        Text("Watch not paired with iPhone")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else if !connectivityManager.isWatchReachable {
                                    // Check how long since activation started
                                    if let startTime = connectivityManager.sessionStartTime {
                                        let elapsed = Date().timeIntervalSince(startTime)
                                        if elapsed < 60 && connectivityManager.sessionActivated {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Waiting for watch app... (up to 60s)")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                                Text("Make sure the watch app is open")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Watch paired but not reachable")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                                Text("Open the GaitGuardAI app on your watch")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Watch paired but not reachable")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                            Text("Open the GaitGuardAI app on your watch")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                } else {
                                    Text("No events received yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if connectivityManager.watchSessionActive {
                            Circle()
                                .fill(connectivityManager.isWatchCalibrating ? Color.orange : Color.green)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke((connectivityManager.isWatchCalibrating ? Color.orange : Color.green).opacity(0.3), lineWidth: 2)
                                        .scaleEffect(1.5)
                                        .opacity(connectivityManager.isWatchReachable ? 1 : 0)
                                        .animation(
                                            Animation.easeInOut(duration: 1.5)
                                                .repeatForever(autoreverses: true),
                                            value: connectivityManager.isWatchReachable
                                        )
                                )
                        }
                    }
                } header: {
                    Text("Connection Status")
                }
                
                // Assist Events Section
                Section {
                    if connectivityManager.assistEvents.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.path")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No events yet")
                                    .foregroundColor(.secondary)
                                Text("Events will appear here in real-time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        ForEach(connectivityManager.assistEvents.indices.reversed(), id: \.self) { index in
                            let event = connectivityManager.assistEvents[index]
                            EventRowView(event: event, isNewest: index == connectivityManager.assistEvents.count - 1)
                        }
                    }
                } header: {
                    HStack {
                        Text("Assist Events")
                        Spacer()
                        Text("\(connectivityManager.assistEvents.count)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } footer: {
                    if !connectivityManager.assistEvents.isEmpty {
                        Text("Events update in real-time as they occur on your watch")
                            .font(.caption)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !connectivityManager.assistEvents.isEmpty {
                        Button("Clear") {
                            connectivityManager.clearEvents()
                        }
                    }
                }
            }
            .onAppear {
                connectivityManager.updateConnectionStatus()
                startConnectionMonitoring()
            }
            .onDisappear {
                stopConnectionMonitoring()
            }
        }
        .navigationTitle("GaitGuardAI")
    }
    
    private func startConnectionMonitoring() {
        // Update connection status every second for real-time monitoring
        let manager = connectivityManager
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Force real connection check
            manager.updateConnectionStatus()
            
            // Also trigger reachability check
            if let session = manager.wcSession {
                // Accessing isReachable triggers a real check
                _ = session.isReachable
            }
        }
    }
    
    private func stopConnectionMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

struct EventRowView: View {
    let event: AssistEvent
    let isNewest: Bool
    
    var body: some View {
        HStack {
            // Event type icon
            Image(systemName: event.type == "start" ? "play.circle.fill" : "arrow.turn.up.right.circle.fill")
                .foregroundColor(event.type == "start" ? .blue : .orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(event.type.capitalized) Assist")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.timestamp, style: .date)
                        .font(.caption)
                    if let duration = event.duration {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1fs", duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.secondary)
                
                // Severity indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index < Int(event.severity * 3) ? severityColor(event.severity) : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                    Text(String(format: "%.0f%%", event.severity * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isNewest {
                Text("NEW")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.3), value: isNewest)
    }
    
    private func severityColor(_ severity: Double) -> Color {
        if severity < 0.33 {
            return .green
        } else if severity < 0.66 {
            return .yellow
        } else {
            return .red
        }
    }
}
