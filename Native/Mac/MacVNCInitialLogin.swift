#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
/// A saved login may start one connection for a new window. Consuming the load
/// before reading also prevents a later unlock from retrying unavailable data.
struct MacVNCInitialLogin {
    private(set) var loaded = false
    struct Loaded<Login> {
        let login: Login
        let shouldConnect: Bool
    }
    mutating func loadIfNeeded<Login>(canAccess: Bool, hasExplicitLogin: Bool, usable: (Login) -> Bool,
                                     read: () throws -> Login?) throws -> Loaded<Login>? {
        guard canAccess, !loaded else { return nil }
        loaded = true
        guard !hasExplicitLogin, let login = try read() else { return nil }
        return Loaded(login: login, shouldConnect: usable(login))
    }
}
#endif
