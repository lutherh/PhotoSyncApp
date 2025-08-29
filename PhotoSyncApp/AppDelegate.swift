import UIKit
import os.log

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger.withBundleSubsystem(category: "AppDelegate")
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.log("didFinishLaunchingWithOptions")
        // Prepare services early
        _ = UploadService.shared
        _ = PhotoSyncManager.shared
        
        return true
    }
    
    // Background URLSession completion handler to wake the app when uploads finish
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
    logger.log("handleEventsForBackgroundURLSession identifier=\(identifier, privacy: .public)")
        UploadService.shared.setBackgroundCompletionHandler(completionHandler, for: identifier)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
    logger.log("applicationDidEnterBackground scheduling tasks")
        BackgroundScheduler.shared.scheduleRefresh()
        BackgroundScheduler.shared.scheduleProcessing()
    }
}