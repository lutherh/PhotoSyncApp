import SwiftUI
import os.log

@main
struct PhotoSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    private let logger = Logger.withBundleSubsystem(category: "App")
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    logger.log("App WindowGroup appeared. hasPhotoAccess=\(self.appState.hasPhotoAccess, privacy: .public)")
                    // BGTasks are now registered in AppDelegate.didFinishLaunching per Apple guidance
                }
        }
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var hasPhotoAccess: Bool = PermissionsManager.currentAuthorizationIsFullAccess
    @Published var syncStatus: String = "Idle"
    @Published var lastSync: Date? = nil
    // Live summary counters for current/last sync session
    @Published var uploadedCount: Int = 0
    @Published var existsCount: Int = 0
    private init() {}
}