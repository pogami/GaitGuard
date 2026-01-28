// GaitGuardAIiPhoneApp.swift
import SwiftUI

@main
struct GaitGuardAIiPhoneApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}

