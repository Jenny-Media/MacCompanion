import SwiftUI
import SwiftTerm
import Citadel
import LocalAuthentication

@main struct VisionOSFeasibilityApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Native visionOS dependency and input probe").font(.title)
                ProbeTerminal().frame(minWidth: 500, minHeight: 250)
                InputProbe().frame(height: 200)
                UIKitInputProbe().frame(height: 120)
            }.padding()
        }.defaultSize(width: 1100, height: 600)
    }
}

struct UIKitInputProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> PanProbeView { PanProbeView() }
    func updateUIView(_ view: PanProbeView, context: Context) {}
}
final class PanProbeView: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        text = "UIKit pan: waiting"; textAlignment = .center
        backgroundColor = .systemTeal; isUserInteractionEnabled = true
        accessibilityIdentifier = "vision-pan-probe"
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let p = gesture.translation(in: self)
        text = "UIKit pan: \(Int(p.x)), \(Int(p.y)); state: \(gesture.state.rawValue)"
    }
}
struct ProbeTerminal: UIViewRepresentable {
    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.feed(text: "Native SwiftTerm on visionOS\r\nUnicode: 中文 · café\r\n")
        _ = CompanionVNCSession()
        _ = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return terminal
    }
    func updateUIView(_ view: TerminalView, context: Context) {}
}
struct InputProbe: View {
    @State private var point = CGPoint.zero
    @State private var events = 0
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.blue.opacity(0.25))
            Text("Selection/drag location: \(Int(point.x)), \(Int(point.y)); events: \(events)").accessibilityIdentifier("vision-input-location")
        }.contentShape(Rectangle())
            .accessibilityIdentifier("vision-input-probe")
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                point = CGPoint(x: value.startLocation.x + value.translation.width,
                                y: value.startLocation.y + value.translation.height)
                events += 1
            })
            .simultaneousGesture(SpatialTapGesture().onEnded { point = $0.location; events += 1 })
    }
}
