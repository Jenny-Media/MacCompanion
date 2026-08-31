import Foundation

public struct KeepalivePingBodyV0: WireBody {
    public static let kind = WireMessageKind.keepalivePing

    public init() {}

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [])
    }

    public func validate() throws {}
}

public struct KeepalivePongBodyV0: WireBody {
    public static let kind = WireMessageKind.keepalivePong

    public init() {}

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [])
    }

    public func validate() throws {}
}
