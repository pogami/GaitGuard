import SwiftUI

struct ContentView: View {
    @StateObject private var engine = MotionDetector()
    // 1. Reference the SessionManager from the environment
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isActive = false
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundStyle)
                .ignoresSafeArea()
            
            // No scrolling: choose the first layout that fits vertically.
            ViewThatFits(in: .vertical) {
                mainLayout(padding: 10, iconSize: 32, showSubtitle: true)
                mainLayout(padding: 8, iconSize: 28, showSubtitle: false)
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

    private func mainLayout(padding: CGFloat, iconSize: CGFloat, showSubtitle: Bool) -> some View {
        VStack(spacing: 8) {
            header(iconSize: iconSize)
            
            VStack(spacing: 2) {
                Text(statusTitle)
                    .font(.system(.headline, design: .rounded).bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                
                if showSubtitle {
                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            
            statsCompact
            
            Spacer(minLength: 0)
            
            controls
        }
        .padding(.top, 6)
        .padding(.horizontal, padding)
        .padding(.bottom, 8)
    }

    private func header(iconSize: CGFloat) -> some View {
        let icon = statusIcon
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon.name)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(icon.color)
                .symbolEffect(.pulse, isActive: isActive && engine.isMonitoring)
                .frame(width: max(30, iconSize + 2))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("GaitGuard")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(isActive ? "Right wrist" : "Wear right wrist")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            Spacer(minLength: 0)
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
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

    private var statsCompact: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assists")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(engine.assistsToday)")
                    .font(.system(.headline, design: .rounded).bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Last")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(engine.lastAssistText)
                    .font(.system(.headline, design: .rounded).bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var settingsSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { showingSettings = false }
                    .font(.subheadline.bold())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text("\(Int(engine.settings.sensitivity * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $engine.settings.sensitivity, in: 0.0...1.0, step: 0.01)
                
                Text("Higher sensitivity cues sooner (more false alarms).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Testing")
                    .font(.subheadline.bold())
                
                Text("Note: Watch Simulator may not vibrate. Test on a real watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Button("Test Haptic") {
                        engine.testHaptic()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Sim Start") {
                        engine.simulateAssist(kind: .start)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Sim Turn") {
                    engine.simulateAssist(kind: .turn)
                }
                .buttonStyle(.bordered)
                
                HStack {
                    Text("State")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(engine.state.rawValue)
                        .font(.caption2.bold())
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
