#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Darwin
import Foundation
import Observation
import UIKit

/// Local advertisements supply presentation only. No discovered route is dialed.
@MainActor @Observable final class DirectMacDiscoveryV1: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private(set) var identities: [DirectMacDetectedIdentity] = []
    private(set) var scanning = false
    private(set) var unavailable = false
    @ObservationIgnored var updated: (() -> Void)?
    @ObservationIgnored private var browsers: [NetServiceBrowser] = []
    @ObservationIgnored private var services: [String: NetService] = [:]
    @ObservationIgnored private var deviceInfo: [String: NetService] = [:]
    @ObservationIgnored private var resolved: [String: DirectMacDetectedIdentity] = [:]
    @ObservationIgnored private var models: [String: String] = [:]
    @ObservationIgnored private var deadline: Task<Void, Never>?

    @discardableResult func start() -> Bool {
        guard !scanning, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { return false }
        stop()
        identities = []; resolved = [:]; models = [:]; unavailable = false; scanning = true
        for type in ["_rfb._tcp.", "_ssh._tcp."] {
            let browser = NetServiceBrowser()
            browser.delegate = self; browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        return true
    }
    func stop() {
        deadline?.cancel(); deadline = nil; scanning = false
        for browser in browsers { browser.delegate = nil; browser.stop() }
        for service in services.values { service.delegate = nil; service.stop() }
        for service in deviceInfo.values { service.delegate = nil; service.stopMonitoring(); service.stop() }
        browsers = []; services = [:]; deviceInfo = [:]
        // Cancellation discards partial resolutions; only completed scans publish metadata.
    }
    private func key(_ service: NetService) -> String { service.domain + "|" + service.type + "|" + service.name }
    private func instance(_ service: NetService) -> String { service.domain + "|" + service.name }
    private func finish() {
        guard scanning, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { stop(); return }
        identities = resolved.keys.sorted().compactMap { key in
            guard var identity = resolved[key], let service = services[key] else { return nil }
            identity.modelIdentifier = models[instance(service)]
            return identity
        }
        stop()
        updated?()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard scanning, browsers.contains(where: { $0 === browser }), services.count < 128,
              DirectMacDetectedIdentity.cleanName(service.name) != nil,
              deviceInfo.count < 128 || deviceInfo[instance(service)] != nil else { return }
        let key = key(service)
        guard services[key] == nil else { return }
        services[key] = service; service.delegate = self
        service.resolve(withTimeout: 3)
        let instance = instance(service)
        if deviceInfo[instance] == nil {
            // Apple's device-info is a TXT record, and need not have an SRV/PTR
            // advertisement. Monitor its exact name rather than resolve a port.
            let info = NetService(domain: service.domain, type: "_device-info._tcp.", name: service.name)
            deviceInfo[instance] = info; info.delegate = self; info.startMonitoring()
        }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard scanning, browsers.contains(where: { $0 === browser }) else { return }
        let key = key(service)
        services.removeValue(forKey: key)?.stop(); resolved.removeValue(forKey: key)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browsers.contains(where: { $0 === browser }) else { return }
        unavailable = true
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = key(sender)
        guard scanning, services[key] === sender, let host = sender.hostName,
              let name = DirectMacDetectedIdentity.cleanName(sender.name),
              (1...65535).contains(sender.port), host.utf8.count <= 255 else { return }
        let addresses = (sender.addresses ?? []).prefix(16).compactMap { data -> String? in
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress, bytes.count >= MemoryLayout<sockaddr>.size else { return nil }
                let address = base.assumingMemoryBound(to: sockaddr.self)
                guard (address.pointee.sa_family == AF_INET && bytes.count >= MemoryLayout<sockaddr_in>.size)
                    || (address.pointee.sa_family == AF_INET6 && bytes.count >= MemoryLayout<sockaddr_in6>.size) else { return nil }
                var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(address, socklen_t(bytes.count), &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        resolved[key] = .init(name: name, host: host, addresses: addresses, port: sender.port,
            connection: sender.type == "_ssh._tcp." ? .terminal : .desktop)
    }
    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        let instance = instance(sender)
        guard scanning, deviceInfo[instance] === sender, data.count <= 4096,
              let bytes = NetService.dictionary(fromTXTRecord: data)["model"],
              let text = String(data: bytes, encoding: .utf8),
              let model = DirectMacDetectedIdentity.cleanModel(text) else { return }
        models[instance] = model
    }
}
#endif
