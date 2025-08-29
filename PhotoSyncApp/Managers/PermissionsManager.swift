import Foundation
import Photos

enum PermissionsManager {
    static var currentAuthorizationIsFullAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited: // limited is not "full", but we'll encourage full access
            return status == .authorized
        case .denied, .restricted, .notDetermined: return false
        @unknown default: return false
        }
    }
    
    static func requestPhotoAccess(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            completion(status == .authorized)
        }
    }
}