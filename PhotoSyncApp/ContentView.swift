import SwiftUI
import Photos
import os.log

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    private let logger = Logger.withBundleSubsystem(category: "UI")
    @State private var latestUrls: [URL] = []
    
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sync Status")
                            .font(.headline)
                        if !latestUrls.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(latestUrls.enumerated()), id: \.offset) { _, url in
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .empty:
                                                ProgressView()
                                                    .frame(width: 90, height: 90)
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                                    .frame(width: 90, height: 90)
                                                    .clipped()
                                                    .cornerRadius(8)
                                            case .failure:
                                                Image(systemName: "photo")
                                                    .frame(width: 90, height: 90)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .cornerRadius(8)
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 100)
                        }
                        ScrollView {
                            Text(appState.syncStatus)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 120)
                        HStack(spacing: 12) {
                            Label("Uploaded: \(appState.uploadedCount)", systemImage: "arrow.up.circle")
                            Label("Exists: \(appState.existsCount)", systemImage: "checkmark.circle")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                Task { @MainActor in
                    do {
                        latestUrls = try await PresignAPI.shared.getLatest(limit: 3)
                    } catch {
                        logger.error("Failed loading latest images: \(error.localizedDescription)")
                    }
                }
            }
            .onChange(of: appState.lastSync) { _ in
                Task { @MainActor in
                    do { latestUrls = try await PresignAPI.shared.getLatest(limit: 3) } catch { }
                }
            }
        }
    }
}