#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Darwin
import Foundation

enum DirectMacConnection: String, Codable, CaseIterable, Identifiable {
    case desktop, terminal, trackpad
    var id: String { rawValue }
    var title: String {
        switch self { case .desktop: "Desktop"; case .terminal: "Terminal"; case .trackpad: "Trackpad & Keyboard" }
    }
    var symbol: String {
        switch self { case .desktop: "macwindow"; case .terminal: "terminal"; case .trackpad: "rectangle.and.hand.point.up.left" }
    }
    var actionTitle: String { "Open " + title }
    var inputOnly: Bool { self == .trackpad }
    var terminalMode: Bool { self == .terminal }
}

enum DirectMacFamily: String {
    case unknown, macBook, macBookAir, macBookPro, iMac, macMini, macStudio, macPro
    var title: String {
        switch self {
        case .unknown: "Mac"; case .macBook: "MacBook"; case .macBookAir: "MacBook Air"
        case .macBookPro: "MacBook Pro"; case .iMac: "iMac"; case .macMini: "Mac mini"
        case .macStudio: "Mac Studio"; case .macPro: "Mac Pro"
        }
    }
    var symbol: String {
        switch self {
        case .macBook, .macBookAir, .macBookPro: "laptopcomputer"
        case .macMini: "macmini"; case .macStudio: "macstudio"; case .macPro: "macpro.gen3"
        case .unknown, .iMac: "desktopcomputer"
        }
    }
    static func detect(_ identifier: String?) -> Self {
        guard let identifier else { return .unknown }
        // Apple's opaque identifiers are not ordered by chassis. Only explicit
        // reviewed IDs are classified; future IDs keep a generic icon.
        switch identifier {
        case "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13", "Mac16,12", "Mac16,13", "Mac17,3", "Mac17,4": return .macBookAir
        case "Mac14,5", "Mac14,6", "Mac14,7", "Mac14,9", "Mac14,10", "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11", "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8", "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9": return .macBookPro
        case "Mac14,3", "Mac14,12", "Mac16,10", "Mac16,11", "Mac17,16", "Mac18,5": return .macMini
        case "Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14", "Mac15,14", "Mac16,9", "Mac17,14", "Mac17,15": return .macStudio
        case "Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3": return .iMac
        case "Mac14,8": return .macPro
        default: break
        }
        let families: [(String, Self)] = [("MacBookPro", .macBookPro), ("MacBookAir", .macBookAir),
            ("MacBook", .macBook), ("iMacPro", .iMac), ("iMac", .iMac), ("Macmini", .macMini),
            ("MacStudio", .macStudio), ("MacPro", .macPro)]
        return families.first { identifier.range(of: "^" + $0.0 + "[0-9]+,[0-9]+$", options: .regularExpression) != nil }?.1 ?? .unknown
    }
}

struct DirectMacDetectedIdentity: Equatable {
    let name: String
    let host: String
    let addresses: [String]
    let port: Int
    let connection: DirectMacConnection
    var modelIdentifier: String?

    static func cleanName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count), !name.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
        }) else { return nil }
        return name
    }
    static func cleanModel(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,-")
        guard (1...128).contains(value.utf8.count), value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
    static func endpointKey(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "" }
        let parts = value.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        let ip = String(parts[0])
        var bytes = in6_addr()
        if inet_pton(AF_INET6, ip, &bytes) == 1 {
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if inet_ntop(AF_INET6, &bytes, &text, socklen_t(text.count)) != nil {
                let canonical = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                return canonical + (parts.count == 2 ? "%" + parts[1] : "")
            }
        }
        return value.hasSuffix(".") ? String(value.dropLast()) : value
    }
    func matches(addresses configured: [String], port savedPort: Int) -> Bool {
        guard port == savedPort else { return false }
        let keys = Set(([host] + addresses).map(Self.endpointKey))
        return configured.contains { keys.contains(Self.endpointKey($0)) }
    }
    func matches(_ mac: DirectMacRecordV1) -> Bool {
        matches(addresses: mac.addresses, port: connection == .terminal ? mac.sshPort : mac.port)
    }
    static func match(_ mac: DirectMacRecordV1, in identities: [Self]) -> Self? {
        let matches = identities.filter { $0.matches(mac) }
        guard Set(matches.map { endpointKey($0.host) }).count == 1 else { return nil }
        guard var selected = matches.first(where: { $0.connection == .desktop }) ?? matches.first else { return nil }
        let models = Set(matches.compactMap(\.modelIdentifier))
        selected.modelIdentifier = models.count == 1 ? models.first : nil
        return selected
    }
}
#endif
