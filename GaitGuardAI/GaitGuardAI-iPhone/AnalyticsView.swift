import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Cards
                    HStack(spacing: 15) {
                        StatCard(
                            title: "Total Events",
                            value: "\(connectivityManager.assistEvents.count)",
                            icon: "waveform.path",
                            color: .blue
                        )
                        StatCard(
                            title: "Today",
                            value: "\(eventsToday)",
                            icon: "calendar",
                            color: .green
                        )
                    }
                    .padding(.horizontal)
                    
                    // Live Accelerometer Data
                    if !connectivityManager.liveAccelerometerData.isEmpty {
                        LiveAccelerometerChart(data: connectivityManager.liveAccelerometerData)
                            .frame(height: 250)
                            .padding()
                        
                        // Calibration Results
                        if let calibration = connectivityManager.lastCalibrationResults {
                            CalibrationResultsCard(results: calibration)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Events by Type
                    if !connectivityManager.assistEvents.isEmpty {
                        EventsByTypeChart(events: connectivityManager.assistEvents)
                            .frame(height: 200)
                            .padding()
                        
                        // Events by Hour
                        EventsByHourChart(events: connectivityManager.assistEvents)
                            .frame(height: 200)
                            .padding()
                        
                        // Severity Distribution
                        SeverityChart(events: connectivityManager.assistEvents)
                            .frame(height: 200)
                            .padding()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No data yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Analytics will appear here once events are recorded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Analytics")
        }
    }
    
    private var eventsToday: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return connectivityManager.assistEvents.filter { event in
            calendar.startOfDay(for: event.timestamp) == today
        }.count
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EventsByTypeChart: View {
    let events: [AssistEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events by Type")
                .font(.headline)
                .padding(.horizontal)
            
            let startCount = events.filter { $0.type == "start" }.count
            let turnCount = events.filter { $0.type == "turn" }.count
            
            Chart {
                BarMark(
                    x: .value("Type", "Start"),
                    y: .value("Count", startCount)
                )
                .foregroundStyle(.blue)
                
                BarMark(
                    x: .value("Type", "Turn"),
                    y: .value("Count", turnCount)
                )
                .foregroundStyle(.orange)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding()
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EventsByHourChart: View {
    let events: [AssistEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events by Hour of Day")
                .font(.headline)
                .padding(.horizontal)
            
            let hourData = Dictionary(grouping: events) { event in
                Calendar.current.component(.hour, from: event.timestamp)
            }.mapValues { $0.count }
            
            Chart {
                ForEach(Array(hourData.keys.sorted()), id: \.self) { hour in
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Count", hourData[hour] ?? 0)
                    )
                    .foregroundStyle(.green.gradient)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisGridLine()
                    if let intValue = value.as(Int.self) {
                        AxisValueLabel("\(intValue)")
                    } else {
                        AxisValueLabel()
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding()
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SeverityChart: View {
    let events: [AssistEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Severity Distribution")
                .font(.headline)
                .padding(.horizontal)
            
            let low = events.filter { $0.severity < 0.33 }.count
            let medium = events.filter { $0.severity >= 0.33 && $0.severity < 0.66 }.count
            let high = events.filter { $0.severity >= 0.66 }.count
            
            Chart {
                BarMark(
                    x: .value("Severity", "Low"),
                    y: .value("Count", low)
                )
                .foregroundStyle(.green)
                
                BarMark(
                    x: .value("Severity", "Medium"),
                    y: .value("Count", medium)
                )
                .foregroundStyle(.yellow)
                
                BarMark(
                    x: .value("Severity", "High"),
                    y: .value("Count", high)
                )
                .foregroundStyle(.red)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding()
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Live Accelerometer Data Visualization

struct LiveAccelerometerChart: View {
    let data: [AccelerometerData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Accelerometer Data")
                    .font(.headline)
                Spacer()
                Text("\(data.count) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Show last 100 points for performance
            let displayData = Array(data.suffix(100))
            
            Chart {
                ForEach(Array(displayData.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("X", point.x)
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Z", point.z)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: .stride(by: 20)) { value in
                    AxisGridLine()
                    if let intValue = value.as(Int.self) {
                        AxisValueLabel("\(intValue)")
                    }
                }
            }
            .padding()
            
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("X")
                        .font(.caption2)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Y")
                        .font(.caption2)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Z")
                        .font(.caption2)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Calibration Results Card

struct CalibrationResultsCard: View {
    let results: CalibrationResults
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration Results")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Average:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", results.average))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Std Dev:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", results.standardDeviation))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Baseline Threshold:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", results.baselineThreshold))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Samples:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(results.sampleCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                Text("Calibrated: \(results.timestamp, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
