import Foundation

final class PresignAPI {
    static let shared = PresignAPI()
    private init() {}
    
    struct PresignResponse: Decodable {
        let url: String
        let headers: [String: String]?
    }
    
    func getPresignedPUT(key: String, contentType: String) async throws -> PresignedUpload {
        guard let base = Config.shared.presignBaseURL else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Presign base URL not configured"])
        }
        var comps = URLComponents(url: base.appendingPathComponent("presign"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "contentType", value: contentType)
        ]
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
}