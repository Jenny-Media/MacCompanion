#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
enum TerminalLoginMethod: String, CaseIterable, Identifiable {
    case password = "Password", sshKey = "SSH Key"
    var id: String { rawValue }
}
struct TerminalLoginSelection {
    private(set) var method = TerminalLoginMethod.password
    var username = ""
    private var passwordUsername = ""
    private var keyUsername = ""
    mutating func select(_ method: TerminalLoginMethod) {
        if self.method == .sshKey { keyUsername = username } else { passwordUsername = username }
        self.method = method
        let account = method == .sshKey ? keyUsername : passwordUsername
        if !account.isEmpty { username = account }
    }
    mutating func loadPasswordAccount(_ account: String) {
        passwordUsername = account
        if method == .password { username = account }
    }
    mutating func loadKeyAccount(_ account: String?, preferSelected: Bool) {
        if preferSelected && account == nil { select(.password) }
        keyUsername = account ?? ""
        if preferSelected && account != nil {
            if method == .password { passwordUsername = username }
            method = .sshKey
        }
        if method == .sshKey, !keyUsername.isEmpty { username = keyUsername }
    }
}

#endif
