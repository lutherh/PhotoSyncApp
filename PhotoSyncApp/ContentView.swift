import SwiftUI
import Photos
import os.log

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    private let logger = Logger.withBundleSubsystem(category: "UI")
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                GroupBox {
                    HStack {
                        Image(systemName: appState.hasPhotoAccess ? "checkmark.shield" : "exclamationmark.shield")
                            .foregroundColor(appState.hasPhotoAccess ? .green : .orange)
                        Text(appState.hasPhotoAccess ? "Photo Access: Full Access" : "Photo Access: Not Granted")
                        Spacer()
                    }
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync Status: \(appState.syncStatus)")
                        if let last = appState.lastSync {
                            Text("Last Sync: \(last.formatted())")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if !appState.hasPhotoAccess {
                    Button("Grant Photo Access") {
                        PermissionsManager.requestPhotoAccess { granted in
                            DispatchQueue.main.async {
                                appState.hasPhotoAccess = granted
                                if granted {
                                    PhotoSyncManager.shared.startObservingLibraryChanges()
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Sync Now") {
                    Task {
                        await PhotoSyncManager.shared.syncNewPhotos(trigger: .manual)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.hasPhotoAccess)
                
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }.buttonStyle(.bordered)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configuration")
                        .font(.headline)
                    Text("Presign API: \(Config.shared.presignBaseURL?.absoluteString ?? "Not Set")")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .navigationTitle("Photo Backup")
            .onAppear {
                logger.log("ContentView appeared")
                if appState.hasPhotoAccess {
                    logger.log("Starting library observation")
                    PhotoSyncManager.shared.startObservingLibraryChanges()
                }
            }
        }
    }
}