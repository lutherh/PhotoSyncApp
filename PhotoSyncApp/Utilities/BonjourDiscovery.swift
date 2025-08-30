import Foundation

final class BonjourDiscovery: NSObject {
    static let shared = BonjourDiscovery()
    private override init() {}

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var continuation: CheckedContinuation<URL?, Never>?
    private var resolvedURL: URL?

    func discoverPresignBaseURL(timeout: TimeInterval = 5.0) async -> URL? {
        // Manual override wins
        if let manual = Config.shared.presignBaseURL { return manual }
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.continuation = cont
            self.resolvedURL = nil
            self.services.removeAll()
            self.browser.delegate = self
            // Browse for our custom service
            self.browser.searchForServices(ofType: "_photosync._tcp.", inDomain: "local.")
            // Stop after timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.finishDiscovery()
            }
        }
    }

    private func finishDiscovery() {
        browser.stop()
        let url = resolvedURL
        continuation?.resume(returning: url)
        continuation = nil
    }
}

extension BonjourDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        // Choose hostName if available, else try IP from addresses
        var host: String?
        if let name = sender.hostName { host = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if host == nil {
            for addrData in sender.addresses ?? [] {
                let url = addrData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> URL? in
                    guard let sa = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
                    if sa.pointee.sa_family == sa_family_t(AF_INET) {
                        var addr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let b = withUnsafePointer(to: &addr.sin_addr) {
                            inet_ntop(AF_INET, $0, &buf, socklen_t(INET_ADDRSTRLEN))
                        }
                        if b != nil, let s = String(validatingUTF8: buf) {
                            return URL(string: "http://\(s):\(sender.port)")
                        }
                    }
                    return nil
                }
                if let url = url { resolvedURL = url; break }
            }
        }
        if resolvedURL == nil, let h = host, let url = URL(string: "http://\(h):\(sender.port)") {
            resolvedURL = url
        }
        if resolvedURL != nil { finishDiscovery() }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        // Ignore; we'll finish on timeout if nothing resolves
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        finishDiscovery()
    }
}
