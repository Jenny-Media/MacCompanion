import UIKit
import VisionKit

/// The system interaction stays on a frozen, local image, never on the live
/// remote-input surface. This adapter also owns cancellation of its analysis.
@MainActor
@objc(CompanionVNCTextSelection)
final class CompanionVNCTextSelection: NSObject, ImageAnalysisInteractionDelegate {
    private let analyzer = ImageAnalyzer()
    private let interaction = ImageAnalysisInteraction()
    private weak var imageView: UIImageView?
    private var task: Task<Void, Never>?
    private var generation: UInt = 0
    private var retired = false

    @objc static var supported: Bool { ImageAnalyzer.isSupported }
    @objc private(set) var busy = false
    @objc var enabled = true
    @objc var selectionChanged: (() -> Void)?
    @objc var selectedText: String { retired ? "" : interaction.selectedText }
    @objc var text: String { retired ? "" : interaction.text }

    @objc(initWithImageView:)
    init(imageView: UIImageView) {
        self.imageView = imageView
        super.init()
        interaction.delegate = self
        interaction.preferredInteractionTypes = .textSelection
        interaction.allowLongPressForDataDetectorsInTextMode = false
        // The screen is already in an explicit text-selection tool.
        interaction.selectableItemsHighlighted = true
        interaction.isSupplementaryInterfaceHidden = true
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(interaction)
    }

    @objc(analyzeImage:completion:)
    func analyze(image: UIImage, completion: @escaping (Bool) -> Void) {
        guard !retired, !busy, Self.supported, let pixels = image.cgImage,
              pixels.width > 0, pixels.height > 0,
              pixels.width <= 8192, pixels.height <= 8192,
              pixels.width * pixels.height <= 16 * 1024 * 1024 else {
            completion(false)
            return
        }
        generation &+= 1
        let token = generation
        busy = true
        task = Task { [weak self, analyzer] in
            let result = try? await analyzer.analyze(image, configuration: .init(.text))
            guard let self else { return }
            self.busy = false
            self.task = nil
            guard !self.retired, self.generation == token, !Task.isCancelled else { return }
            let bounded = result.flatMap { $0.transcript.utf16.count <= 65_536 ? $0 : nil }
            self.interaction.analysis = bounded
            // Activate selection after installing analysis; setting the type only
            // before analysis can leave UIKit with no active interaction types.
            self.interaction.preferredInteractionTypes = .textSelection
            self.interaction.selectableItemsHighlighted = true
            completion(bounded?.hasResults(for: .text) == true)
        }
    }

    @objc func cancel() {
        generation &+= 1
        task?.cancel()
        interaction.resetTextSelection()
        interaction.analysis = nil
    }

    @objc func invalidate() {
        guard !retired else { return }
        retired = true
        enabled = false
        cancel()
        selectionChanged = nil
        imageView?.removeInteraction(interaction)
        imageView = nil
    }

    func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                     for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
        !retired && enabled && !busy
    }

    func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
        guard !retired else { return }
        selectionChanged?()
    }

    deinit { task?.cancel() }
}
