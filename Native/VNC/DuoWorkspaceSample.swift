#if os(iOS) && DEBUG && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

/// An explicit local fixture; it never restores or connects a saved Mac.
struct DuoWorkspaceSample: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { CompanionVNCDuoSampleWorkspace() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
