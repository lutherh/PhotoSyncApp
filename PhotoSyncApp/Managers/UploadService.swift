import Foundation
import os.log
import UniformTypeIdentifiers

struct PresignedUpload {
    let url: URL
    let headers: [String: String] // Optional extra headers from your presign API
}

struct UploadTaskMetadata: Codable {
    let assetLocalId: String
    let s3Key: String
}

final class UploadService: NSObject {
    static let shared = UploadService()
    
    private let logger = Logger.withBundleSubsystem(category: "Upload")
    private var sessionIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "dk.glutter.dk.PhotoSyncApp"
        return "\(bundleId).bg"
    }
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = true
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.networkServiceType = .background
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
    }
    
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        backgroundCompletionHandlers[identifier] = handler
    }
    
    func enqueueUpload(fileURL: URL, to presigned: PresignedUpload, contentType: String, metadata: UploadTaskMetadata) throws {
        var request = URLRequest(url: presigned.url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in presigned.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let task = session.uploadTask(with: request, fromFile: fileURL)
        // Encode metadata into taskDescription so we can mark completion later
        let enc = try JSONEncoder().encode(metadata)
        task.taskDescription = String(data: enc, encoding: .utf8)
        task.resume()
        // Do not remove temp file immediately; let URLSession own a file copy reference.
        // Optionally schedule deletion post-completion in delegate.
    }
}

extension UploadService: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger.error("URLSession became invalid: \(error?.localizedDescription ?? "nil")")
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Called when all background tasks are done
        if let handler = backgroundCompletionHandlers[session.configuration.identifier ?? ""] {
            backgroundCompletionHandlers[session.configuration.identifier ?? ""] = nil
            handler()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            // Clean up temp file if path available in transactionMetrics?
        }
        guard error == nil else {
            logger.error("Upload failed: \(error!.localizedDescription)")
            return
        }
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? -1
    if 200..<300 ~= code {
            Task { @MainActor in
                AppState.shared.syncStatus = "Upload completed."
        AppState.shared.uploadedCount += 1
            }
        } else {
            logger.error("Upload HTTP error: \(code)")
        }
    }
}