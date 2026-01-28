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
            ScrollView {
                VStack(spacing: 20) {
                    // Stats cards
                    statsCards
                    
                    // Timeline
                    timelineSection
                    
                    // Chart
                    chartSection
                }
                .padding()
            }
            .navigationTitle("GaitGuard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Timeframe", selection: $selectedTimeframe) {
                            ForEach(Timeframe.allCases, id: \.self) { tf in
                                Text(tf.rawValue).tag(tf)
                            }
                        }
                        
                        Button(role: .destructive) {
                            connectivity.clearEvents()
                        } label: {
                            Label("Clear Data", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
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
                icon: "chart.bar",
                color: .green
            )
        }
    }
    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Assists")
                .font(.headline)
            
            if filteredEvents.isEmpty {
                Text("No assists recorded yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(filteredEvents.prefix(10), id: \.timestamp) { event in
                    TimelineRow(event: event)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Assists")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart(dailyData) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .frame(height: 200)
            } else {
                Text("Charts require iOS 16+")
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title.bold())
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TimelineRow: View {
    let event: AssistEvent
    
    var body: some View {
        HStack {
            Circle()
                .fill(event.type == "start" ? Color.orange : Color.purple)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type == "start" ? "Start Assist" : "Turn Assist")
                    .font(.subheadline.bold())
                
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DailyData: Identifiable {
    let id = UUID()
    let day: Date
    let count: Int
}

