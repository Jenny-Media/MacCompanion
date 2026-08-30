import SwiftUI
import UIKit

@main
struct ClientUIHarnessApp: App {
    @StateObject private var lifecycle = HarnessApplicationLifecycleModel()

    init() {
        if Self.isLab {
            UIView.setAnimationsEnabled(false)
        }
    }

    private static var isLab: Bool {
        ProcessInfo.processInfo.arguments.contains("--network-control-lab")
            || ProcessInfo.processInfo.arguments.contains("--integrated-control-lab")
            || ProcessInfo.processInfo.arguments.contains("--authenticated-journey")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--authenticated-journey") {
                    AuthenticatedJourneyView()
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                } else if ProcessInfo.processInfo.arguments.contains("--integrated-control-lab") {
                    IntegratedControlLabView()
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                } else if ProcessInfo.processInfo.arguments.contains("--network-control-lab") {
                    NavigationStack { NetworkControlLabView() }
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                } else {
                    HarnessContentView()
                }
            }
                .environmentObject(lifecycle)
                .task { if !Self.isLab { await lifecycle.start() } }
        }
    }
}
