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
        VStack(spacing: 0) {
            header(iconSize: iconSize)
            
            Spacer(minLength: 0)
            
            // Status indicator with icon
            VStack(spacing: 2) {
                Image(systemName: statusIcon.name)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(statusIcon.color)
                    .symbolEffect(.pulse, isActive: isActive && engine.isMonitoring)
                
                Text(statusTitle)
                    .font(.system(.footnote, design: .rounded).bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            statsCompact
            
            Spacer(minLength: 4)
            
            controls
        }
        .padding(.horizontal, padding)
        .padding(.bottom, 2)
        .ignoresSafeArea(.all, edges: .top) // Allow content to move into the very top area
    }

    private func header(iconSize: CGFloat) -> some View {
        HStack(alignment: .center) {
            Text("GaitGuard")
                .font(.system(.body, design: .rounded).bold())
                .lineLimit(1)
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 0) // Remove the padding to move it to the very top
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
        HStack(spacing: 4) {
            // Assists count
            VStack(spacing: 0) {
                Text("\(engine.assistsToday)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("ASSISTS")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            
            // Last assist time
            VStack(spacing: 0) {
                Text(engine.lastAssistText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("LAST")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var controls: some View {
        Button {
            isActive.toggle()
        } label: {
            Text(isActive ? "STOP" : "START")
                .font(.system(.body, design: .rounded).bold())
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(isActive ? .red : .white)
        .foregroundStyle(isActive ? .white : .blue)
    }

    private var settingsSheet: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    Button("Done") { showingSettings = false }
                        .font(.subheadline.bold())
                }
                .padding(.bottom, 4)
                
                // Sensitivity
                VStack(spacing: 6) {
                    HStack {
                        Text("Sensitivity")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(engine.settings.sensitivity * 100))%")
                            .font(.subheadline.bold())
                    }
                    Slider(value: $engine.settings.sensitivity, in: 0.0...1.0, step: 0.01)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                
                // Testing buttons in a grid
                VStack(spacing: 6) {
                    Button("Test Haptic") {
                        engine.testHaptic()
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    
                    HStack(spacing: 6) {
                        Button("Sim Start") {
                            engine.simulateAssist(kind: .start)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        
                        Button("Sim Turn") {
                            engine.simulateAssist(kind: .turn)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                
                // State indicator (compact)
                HStack {
                    Text("State:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(engine.state.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if !isActive { 
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        switch engine.state {
        case .cueingStartAssist, .cueingTurnAssist:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.orange, Color(red: 0.9, green: 0.4, blue: 0.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .cooldown:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.purple, Color(red: 0.5, green: 0.2, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.5, blue: 0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
