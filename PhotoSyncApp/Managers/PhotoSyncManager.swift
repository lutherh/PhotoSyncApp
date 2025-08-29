import Foundation
import Photos
import os.log

final class PhotoSyncManager: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoSyncManager()
    
    private let indexStore = UploadedIndexStore.shared
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
            self.updateStatus("Scanning library...")
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var queued = 0
        assets.enumerateObjects { asset, _, stop in
            if queued >= limit { stop.pointee = true; return }
            if !self.indexStore.isUploaded(asset.localIdentifier) {
                queued += 1
                Task.detached(priority: .utility) {
                    await self.prepareAndUpload(asset: asset)
                }
            }
        }
        
        await MainActor.run {
            self.updateStatus(queued > 0 ? "Queued \(queued) upload(s)..." : "Nothing to sync.")
            AppState.shared.lastSync = Date()
        }
    }
    
    private func prepareAndUpload(asset: PHAsset) async {
        // Get original resource
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) ??
                PHAssetResource.assetResources(for: asset).first else {
            logger.error("No resource found for asset \(asset.localIdentifier)")
            return
        }
        
        // Temp file URL
        let fileExt = (resource.originalFilename as NSString).pathExtension
        let fileName = resource.originalFilename.isEmpty ? "\(UUID().uuidString).\(fileExt.isEmpty ? "jpg" : fileExt)" : resource.originalFilename
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExt.isEmpty ? "jpg" : fileExt)
        
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
        
        // Determine content type
        let contentType = MimeType.guess(fromPathExtension: tmpURL.pathExtension)
        
        // Compute S3 object key (customize to your pathing preference)
        let created = asset.creationDate ?? Date()
        let yyyy = DateFormatter.cached(format: "yyyy").string(from: created)
        let mm = DateFormatter.cached(format: "MM").string(from: created)
        let dd = DateFormatter.cached(format: "dd").string(from: created)
        let s3Key = "photos/\(yyyy)/\(mm)/\(dd)/\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_")).\(tmpURL.pathExtension)"
        
        // Request presigned URL
        guard let presign = try? await PresignAPI.shared.getPresignedPUT(key: s3Key, contentType: contentType) else {
            logger.error("Failed to get presigned URL for key \(s3Key)")
            return
        }
        
        // Start background upload
        let metadata = UploadTaskMetadata(assetLocalId: asset.localIdentifier, s3Key: s3Key)
        do {
            try UploadService.shared.enqueueUpload(fileURL: tmpURL, to: presign, contentType: contentType, metadata: metadata)
            await MainActor.run {
                AppState.shared.syncStatus = "Uploading \(resource.originalFilename)"
            }
        } catch {
            logger.error("Failed to enqueue upload: \(error.localizedDescription)")
        }
    }
}