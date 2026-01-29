// ContentView.swift (iPhone)
import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var selectedTimeframe: Timeframe = .today
    
    enum Timeframe: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background color that truly fills the screen
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Live Status Card
                        liveStatusCard

                        // Demo controls (lets you see charts + live state without wearing the watch)
                        demoControls
                        
                        // Stats cards
                        statsCards
                        
                        // Timeline
                        timelineSection
                        
                        // Chart
                        chartSection
                        
                        // Bottom padding to ensure scrollability
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8) // Small top margin below title
                }
            }
            .navigationTitle("GaitGuard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Timeframe", selection: $selectedTimeframe) {
                            ForEach(Timeframe.allCases, id: \.self) { tf in
                                Text(tf.rawValue).tag(tf)
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            connectivity.clearEvents()
                        } label: {
                            Label("Clear All Data", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }
    
    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Status")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    Text(statusTitle)
                        .font(.title2.bold())
                        .foregroundStyle(statusColor)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, isActive: isLive)
                }
            }
            
            if isLive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Live Monitoring")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        connectivity.requestCurrentStateFromWatch()
                    } label: {
                        Label("Refresh State", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button {
                        connectivity.requestTelemetryFromWatch()
                    } label: {
                        Label("Request Live Data", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .foregroundStyle(.white)
                }
            }

            // Debug line: helps verify WCSession is actually connected/reachable.
            VStack(alignment: .leading, spacing: 2) {
                Text("WCSession: \(connectivity.wcActivationStateLabel) • reachable: \(connectivity.wcIsReachable ? "yes" : "no")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("paired: \(connectivity.wcIsPaired ? "yes" : "no") • watch app installed: \(connectivity.wcIsWatchAppInstalled ? "yes" : "no")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let at = connectivity.lastTelemetryReceivedAt {
                    Text("last telemetry: \(at, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("last telemetry: —")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let t = connectivity.lastTelemetry {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cadence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f Hz", t.cadenceHz))
                            .font(.headline.bold())
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f rad/s", t.turnRateRadPerSec))
                            .font(.headline.bold())
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f g", t.movementIntensity))
                            .font(.headline.bold())
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Demo / Test")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button {
                    connectivity.addDemoEvents()
                } label: {
                    Label("Add Sample Data", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    if connectivity.isLiveDemoRunning {
                        connectivity.stopLiveDemo()
                    } else {
                        connectivity.startLiveDemo()
                    }
                } label: {
                    Label(connectivity.isLiveDemoRunning ? "Stop Live Demo" : "Start Live Demo",
                          systemImage: connectivity.isLiveDemoRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(connectivity.isLiveDemoRunning ? .red : .green)
                .foregroundStyle(.white)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var isLive: Bool {
        connectivity.remoteState != "off"
    }
    
    private var statusTitle: String {
        switch connectivity.remoteState {
        case "off": return "Guard is Off"
        case "monitoringStill": return "Ready"
        case "monitoringWalking": return "Walking"
        case "cueingStartAssist": return "Assisting: Start"
        case "cueingTurnAssist": return "Assisting: Turn"
        case "cooldown": return "Cooldown"
        default: return "Connected"
        }
    }
    
    private var statusIcon: String {
        switch connectivity.remoteState {
        case "off": return "shield.slash.fill"
        case "monitoringStill": return "bolt.shield.fill"
        case "monitoringWalking": return "figure.walk"
        case "cueingStartAssist", "cueingTurnAssist": return "metronome.fill"
        case "cooldown": return "timer"
        default: return "applewatch"
        }
    }
    
    private var statusColor: Color {
        switch connectivity.remoteState {
        case "off": return .gray
        case "monitoringStill", "monitoringWalking": return .green
        case "cueingStartAssist", "cueingTurnAssist": return .orange
        case "cooldown": return .purple
        default: return .blue
        }
    }
    
    private var statsCards: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Today",
                value: "\(todayCount)",
                icon: "calendar",
                color: .blue
            )
            
            StatCard(
                title: "This Week",
                value: "\(weekCount)",
                icon: "chart.bar.fill",
                color: .green
            )
        }
    }
    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Assists")
                    .font(.title3.bold())
                Spacer()
                Text(selectedTimeframe.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No assists recorded yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredEvents.prefix(10).enumerated().map({$0}), id: \.element.timestamp) { index, event in
                        TimelineRow(event: event)
                        if index < min(filteredEvents.count, 10) - 1 {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Pattern")
                .font(.title3.bold())
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(dailyData) { item in
                        BarMark(
                            x: .value("Day", item.day, unit: .day),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
            } else {
                Text("Charts require iOS 16+")
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // MARK: - Computed
    
    private var todayCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return connectivity.assistEvents.filter { $0.timestamp >= today }.count
    }
    
    private var weekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return connectivity.assistEvents.filter { $0.timestamp >= weekAgo }.count
    }
    
    private var filteredEvents: [AssistEvent] {
        let cutoff: Date
        switch selectedTimeframe {
        case .today:
            cutoff = Calendar.current.startOfDay(for: Date())
        case .week:
            cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        }
        return connectivity.assistEvents.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }
    
    private var dailyData: [DailyData] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        return grouped.map { date, events in
            DailyData(day: date, count: events.count)
        }.sorted { $0.day < $1.day }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.bold())
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded).bold())
                
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 5)
    }
}

struct TimelineRow: View {
    let event: AssistEvent
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(event.type == "start" ? Color.orange.opacity(0.2) : Color.purple.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: event.type == "start" ? "bolt.fill" : "arrow.turn.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(event.type == "start" ? Color.orange : Color.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type == "start" ? "Start Hesitation Assist" : "Turn Assist")
                    .font(.subheadline.bold())
                
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }
}

struct DailyData: Identifiable {
    let id = UUID()
    let day: Date
    let count: Int
}

