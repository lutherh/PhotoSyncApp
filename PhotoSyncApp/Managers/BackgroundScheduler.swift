import Foundation
import BackgroundTasks
import os.log

final class BackgroundScheduler {
    static let shared = BackgroundScheduler()
    private init() {}
    
    // Identifiers derived from bundle id to match Info.plist permitted identifiers
    private var bundleId: String { Bundle.main.bundleIdentifier ?? "dk.glutter.dk.PhotoSyncApp" }
    var refreshTaskId: String { "\(bundleId).refresh" }
    var processingTaskId: String { "\(bundleId).processing" }
    
    func registerTasks() {
    os_log("Registering BGTasks: %{public}@ / %{public}@", refreshTaskId, processingTaskId)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskId, using: nil) { task in
            self.handleProcessing(task: task as! BGProcessingTask)
        }
    }
    
    func scheduleRefresh() {
    os_log("Scheduling BGAppRefresh: %{public}@", refreshTaskId)
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            os_log("Failed to schedule app refresh: %{public}@", "\(error)")
        }
    }
    
    func scheduleProcessing() {
    os_log("Scheduling BGProcessing: %{public}@", processingTaskId)
        let request = BGProcessingTaskRequest(identifier: processingTaskId)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            os_log("Failed to schedule processing: %{public}@", "\(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleRefresh()
        let operation = Task {
            await PhotoSyncManager.shared.syncNewPhotos(trigger: .backgroundRefresh)
        }
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        Task {
            // Allow some time slice; wrap in a timeout window if needed
            await operation.value
            task.setTaskCompleted(success: true)
        }
    }
    
    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing()
        let operation = Task {
            await PhotoSyncManager.shared.syncNewPhotos(limit: 50, trigger: .backgroundProcessing)
        }
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        Task {
            await operation.value
            task.setTaskCompleted(success: true)
        }
    }
}