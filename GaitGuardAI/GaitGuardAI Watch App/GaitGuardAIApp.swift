// GaitGuardAIApp.swift (REMOVE any duplicate SessionManager class from this file)
import SwiftUI

@main
struct GaitGuardAIApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
}
