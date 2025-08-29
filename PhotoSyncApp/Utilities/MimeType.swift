import Foundation
import UniformTypeIdentifiers

enum MimeType {
    static func guess(fromPathExtension ext: String) -> String {
        if #available(iOS 14.0, *),
           let utType = UTType(filenameExtension: ext.lowercased()) {
            return utType.preferredMIMEType ?? defaultFor(ext)
        }
        return defaultFor(ext)
    }
    
    private static func defaultFor(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "tiff", "tif": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}

extension DateFormatter {
    static func cached(format: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = format
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }
}