import Foundation
import CryptoKit
import Photos
import os.log

final class PhotoSyncManager: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoSyncManager()
    
    private let resourceManager = PHAssetResourceManager.default()
    private let logger = Logger.withBundleSubsystem(category: "Sync")
    private var isObserving = false
    
    enum Trigger {
        case manual
        case backgroundRefresh
        case backgroundProcessing
        case libraryChange
    }
    
    private override init() {
        super.init()
    }
    
    func startObservingLibraryChanges() {
        guard !isObserving else { return }
        PHPhotoLibrary.shared().register(self)
        isObserving = true
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            AppState.shared.syncStatus = "New photos detected. Scheduling sync..."
        }
        Task {
            await syncNewPhotos(trigger: .libraryChange)
        }
    }
    
    @MainActor
    private func updateStatus(_ text: String) {
        AppState.shared.syncStatus = text
    }
    
    func syncNewPhotos(limit: Int = 25, trigger: Trigger) async {
        guard PermissionsManager.currentAuthorizationIsFullAccess else {
            await MainActor.run {
                self.updateStatus("No full photo access.")
            }
            return
        }
        
        await MainActor.run {
            AppState.shared.uploadedCount = 0
            AppState.shared.existsCount = 0
            self.updateStatus("Scanning library...")
        }
        
        let fetchOptions = PHFetchOptions()
        // Prioritize newest items first and cap the number fetched
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
    let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    logger.log("Fetched \(assets.count, privacy: .public) images (limit=\(limit, privacy: .public)) sorted desc by creationDate")
        
        var queued = 0
        assets.enumerateObjects { asset, _, _ in
            queued += 1
            Task.detached(priority: .utility) {
                await self.prepareAndUpload(asset: asset)
            }
        }
        
        await MainActor.run {
            self.updateStatus(queued > 0 ? "Queued \(queued) upload(s)..." : "Nothing to sync.")
            AppState.shared.lastSync = Date()
        }
    }
    
    private func prepareAndUpload(asset: PHAsset) async {
    // Get a representative resource (prefer actual photo data, fallback to first available)
    let resources = PHAssetResource.assetResources(for: asset)
    guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto }) ?? resources.first else {
            logger.error("No resource found for asset \(asset.localIdentifier)")
            return
        }
        
    // Prepare names (we'll hash content for cross-device dedupe)
    logger.log("Preparing asset id=\(asset.localIdentifier, privacy: .public) created=\(asset.creationDate?.description ?? "nil", privacy: .public)")
    let fileExtRaw = (resource.originalFilename as NSString).pathExtension
    let chosenExt = fileExtRaw.isEmpty ? "jpg" : fileExtRaw
    // Temp file URL
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(chosenExt)
        
        // Export to a file
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                resourceManager.writeData(for: resource, toFile: tmpURL, options: options) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            logger.error("Failed exporting asset \(asset.localIdentifier): \(error.localizedDescription)")
            return
        }
        
        // Compute SHA-256 of file for content-addressed key
        guard let sha256 = try? computeSHA256Hex(of: tmpURL) else {
            logger.error("Failed to compute SHA-256 for exported file")
            return
        }
    // S3 key: content-addressed for global dedupe
        // Optionally shard by prefix to avoid large listings under one folder
        let prefix1 = String(sha256.prefix(2))
        let prefix2 = String(sha256.dropFirst(2).prefix(2))
        let s3Key = "photos/by-hash/\(prefix1)/\(prefix2)/\(sha256).\(tmpURL.pathExtension)"

        // Check S3 for existence using the content-addressed key
        if let exists = try? await PresignAPI.shared.objectExists(key: s3Key), exists {
            logger.log("S3 object already exists (hash), skipping: \(s3Key, privacy: .public)")
            await MainActor.run { AppState.shared.existsCount += 1 }
            return
        }

        // Determine content type
        let contentType = MimeType.guess(fromPathExtension: tmpURL.pathExtension)

    // Request presigned URL (attach capture date and original filename to metadata)
    let created = asset.creationDate ?? Date()
    guard let presign = try? await PresignAPI.shared.getPresignedPUT(key: s3Key, contentType: contentType, created: created, filename: resource.originalFilename) else {
            logger.error("Failed to get presigned URL for key \(s3Key)")
            return
        }
        
        // Start background upload
        let metadata = UploadTaskMetadata(assetLocalId: asset.localIdentifier, s3Key: s3Key)
        logger.log("Checking S3 existence for key=\(s3Key, privacy: .public)")
        do {
            try UploadService.shared.enqueueUpload(fileURL: tmpURL, to: presign, contentType: contentType, metadata: metadata)
            await MainActor.run {
        AppState.shared.syncStatus = "Uploading \(resource.originalFilename)"
            }
            logger.log("Enqueued upload for key=\(s3Key, privacy: .public) size=\((try? FileManager.default.attributesOfItem(atPath: tmpURL.path)[.size] as? NSNumber)?.intValue ?? -1, privacy: .public)")
        } catch {
            logger.error("Failed to enqueue upload: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers
    private func computeSHA256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) // 1 MB
            if let chunk = data, !chunk.isEmpty {
                hasher.update(data: chunk)
            } else {
                break
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}