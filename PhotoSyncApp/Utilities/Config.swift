import Foundation

final class Config {
    static let shared = Config()
    private init() {}
    
    // Set this in Configuration.plist
    var presignBaseURL: URL? {
        guard let str = value(forKey: "PRESIGN_BASE_URL") as? String, !str.isEmpty else { return nil }
        return URL(string: str)
    }
    
    var bucketName: String? {
        value(forKey: "S3_BUCKET") as? String
    }
    
    private func value(forKey key: String) -> Any? {
        guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist[key]
    }
}