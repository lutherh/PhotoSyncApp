import Foundation

final class UploadedIndexStore {
    static let shared = UploadedIndexStore()
    
    private var uploaded: Set<String> = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "UploadedIndexStore")
    
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("uploaded_index.json")
        load()
    }
    
    func isUploaded(_ localIdentifier: String) -> Bool {
        queue.sync { uploaded.contains(localIdentifier) }
    }
    
    func markUploaded(_ localIdentifier: String) {
        queue.sync {
            uploaded.insert(localIdentifier)
            save()
        }
    }
    
    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            uploaded = Set(arr)
        }
    }
    
    private func save() {
        let data = try? JSONEncoder().encode(Array(uploaded))
        try? data?.write(to: fileURL)
    }
}