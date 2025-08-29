import Foundation

final class PresignAPI {
    static let shared = PresignAPI()
    private init() {}
    
    struct PresignResponse: Decodable {
        let url: String
        let headers: [String: String]?
    }
    struct ExistsResponse: Decodable { let exists: Bool }
    struct LatestItem: Decodable { let key: String; let url: String; let lastModified: String?; let size: Int? }
    struct LatestResponse: Decodable { let items: [LatestItem] }
    
    func getPresignedPUT(key: String, contentType: String, created: Date? = nil, filename: String? = nil) async throws -> PresignedUpload {
        guard let base = Config.shared.presignBaseURL else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Presign base URL not configured"])
        }
        var comps = URLComponents(url: base.appendingPathComponent("presign"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "contentType", value: contentType)
        ]
        if let created = created { items.append(URLQueryItem(name: "created", value: String(Int(created.timeIntervalSince1970 * 1000)))) }
        if let filename = filename { items.append(URLQueryItem(name: "filename", value: filename)) }
        comps.queryItems = items
        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // If your API needs auth, attach headers/tokens here, e.g.:
        // req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "PresignAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Presign API failed"])
        }
        let decoded = try JSONDecoder().decode(PresignResponse.self, from: data)
        guard let urlObj = URL(string: decoded.url) else {
            throw NSError(domain: "PresignAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL returned"])
        }
    return PresignedUpload(url: urlObj, headers: decoded.headers ?? [:])
    }

    func objectExists(key: String) async throws -> Bool {
        guard let base = Config.shared.presignBaseURL else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Presign base URL not configured"])
        }
        var comps = URLComponents(url: base.appendingPathComponent("exists"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [ URLQueryItem(name: "key", value: key) ]
        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "PresignAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Exists API failed"])
        }
        let decoded = try JSONDecoder().decode(ExistsResponse.self, from: data)
        return decoded.exists
    }
}

extension PresignAPI {
    func getLatest(limit: Int = 3) async throws -> [URL] {
        guard let base = Config.shared.presignBaseURL else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Presign base URL not configured"])
        }
        var comps = URLComponents(url: base.appendingPathComponent("latest"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [ URLQueryItem(name: "limit", value: String(limit)) ]
        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "PresignAPI", code: 5, userInfo: [NSLocalizedDescriptionKey: "Latest API failed"])
        }
        let decoded = try JSONDecoder().decode(LatestResponse.self, from: data)
        return decoded.items.compactMap { URL(string: $0.url) }
    }
}