#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacSSHKeyManager: View {
    var mac: DirectMacRecordV1? = nil
    var changed: @MainActor () -> Void = {}
    var body: some View {
        TerminalKeySettings(mac: mac, changed: changed).frame(minWidth: 520, minHeight: 440)
    }
}
#endif
