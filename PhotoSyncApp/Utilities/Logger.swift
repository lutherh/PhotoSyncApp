import Foundation
import os.log

// Avoid shadowing Logger's designated initializer to prevent recursion.
extension Logger {
    static func withBundleSubsystem(category: String,
                                    bundle: Bundle = .main,
                                    fallbackSubsystem: String = "PhotoSyncApp") -> Logger {
        let subsystem = bundle.bundleIdentifier ?? fallbackSubsystem
        return Logger(subsystem: subsystem, category: category)
    }
}