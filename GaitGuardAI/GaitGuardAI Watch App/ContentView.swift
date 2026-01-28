import SwiftUI

struct ContentView: View {
    @StateObject private var engine = MotionDetector()
    // 1. Reference the SessionManager from the environment
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isActive = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Spacer(minLength: 6)
                
                header
                
                VStack(spacing: 4) {
                    Text(statusTitle)
                        .font(.system(.headline, design: .rounded).bold())
                        .multilineTextAlignment(.center)
                    
                    Text(statusSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer(minLength: 4)
                
                stats
                
                Spacer(minLength: 6)
                
                controls
            }
            .padding(.horizontal, 10)
            .containerBackground(backgroundStyle, for: .navigation)
            .navigationTitle("GaitGuard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                    .disabled(!isActive) // keep UX simple: settings apply while active
                }
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    // Keep the app alive while monitoring.
                    sessionManager.startSession()
                    engine.startMonitoring()
                } else {
                    engine.stopMonitoring()
                    sessionManager.stopSession()
                }
            }
            .onAppear {
                // Ensure UI matches engine state if view is recreated.
                if engine.isMonitoring {
                    isActive = true
                }
            }
        }
    }

    private var header: some View {
        let icon = statusIcon
        return VStack(spacing: 8) {
            Image(systemName: icon.name)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(icon.color)
                .symbolEffect(.pulse, isActive: isActive && engine.isMonitoring)
            
            Text(isActive ? "Right wrist" : "Wear on right wrist")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Assists today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(engine.assistsToday)")
                    .font(.caption.bold())
            }
            HStack {
                Text("Last assist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(engine.lastAssistText)
                    .font(.caption.bold())
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                isActive.toggle()
            } label: {
                Text(isActive ? "STOP" : "START")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isActive ? .red : .blue)
            
            if isActive {
                Text("Automatic start + turn assist")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }

    private var settingsSheet: some View {
        VStack(spacing: 12) {
            Text("Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text("\(Int(engine.settings.sensitivity * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $engine.settings.sensitivity, in: 0.0...1.0, step: 0.01)
                
                Text("Higher sensitivity triggers cues sooner (more false alarms).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            Button("Done") {
                showingSettings = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var backgroundStyle: AnyShapeStyle {
        if !isActive { return AnyShapeStyle(Color.blue.gradient) }
        switch engine.state {
        case .cueingStartAssist, .cueingTurnAssist:
            return AnyShapeStyle(Color.orange.gradient)
        case .cooldown:
            return AnyShapeStyle(Color.purple.gradient)
        default:
            return AnyShapeStyle(Color.green.gradient)
        }
    }

    private var statusTitle: String {
        if !isActive { return "Guard is Off" }
        switch engine.state {
        case .off:
            return "Starting…"
        case .monitoringStill:
            return "Ready"
        case .monitoringWalking:
            return "Walking"
        case .cueingStartAssist:
            return "Cueing: Start"
        case .cueingTurnAssist:
            return "Cueing: Turn"
        case .cooldown:
            return "Cooldown"
        }
    }

    private var statusSubtitle: String {
        if !isActive { return "Tap START to monitor and cue automatically." }
        switch engine.state {
        case .monitoringStill:
            return "Watching for start hesitation and turning."
        case .monitoringWalking:
            return "Monitoring. Stay upright, eyes up."
        case .cueingStartAssist:
            return "Stand tall. Shift weight. Big step."
        case .cueingTurnAssist:
            return "Turn in stages. Small steps."
        case .cooldown:
            return "Giving her a moment before re-cueing."
        default:
            return "Monitoring gait."
        }
    }

    private var statusIcon: (name: String, color: Color) {
        if !isActive { return ("shield.slash", .gray) }
        switch engine.state {
        case .cueingStartAssist, .cueingTurnAssist:
            return ("metronome.fill", .orange)
        case .cooldown:
            return ("timer", .purple)
        case .monitoringWalking:
            return ("figure.walk", .green)
        case .monitoringStill:
            return ("bolt.shield.fill", .green)
        default:
            return ("bolt.shield.fill", .green)
        }
    }
}
