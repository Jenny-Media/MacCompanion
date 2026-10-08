#if os(iOS)
import CompanionInteractiveClient
import CompanionInteractiveWire
import SwiftUI

/// One session bar remains above the native keyboard through safeAreaInset.
@available(iOS 17.0, *)
struct ClientRemoteSessionBarV0: View {
    @Binding var modifiers: InteractiveModifierMask
    let keyboardVisible: Bool
    let keyboardDisabled: Bool
    let disabled: Bool
    let onKeyboard: () -> Void
    let onKey: (ClientKeyboardActionV0, InteractiveModifierMask) -> Void
    let onOptions: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onKeyboard) {
                Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(keyboardVisible ? "Hide Keyboard" : "Keyboard")
            .accessibilityIdentifier("Remote Keyboard")
            .disabled(keyboardDisabled)

            keyButton("esc", label: "Escape", action: .escape)
            keyButton("⇥", label: "Tab", action: .tab)
            modifierButton("⇧", label: "Shift", mask: .leftShift)
            modifierButton("⌃", label: "Control", mask: .leftControl)
            modifierButton("⌥", label: "Option", mask: .leftOption)
            modifierButton("⌘", label: "Command", mask: .leftCommand)

            Button(action: onOptions) {
                Image(systemName: "ellipsis")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Session options")
            .accessibilityIdentifier("More")
            .disabled(disabled)
        }
        .font(.system(size: 20, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Remote Session Bar")
    }

    private func keyButton(_ title: String, label: String,
                           action: ClientKeyboardActionV0) -> some View {
        Button { onKey(action, modifiers) } label: {
            Text(title)
                .font(title == "esc" ? .system(size: 14, weight: .medium) : .system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("Remote key \(label.lowercased())")
        .disabled(disabled)
    }

    private func modifierButton(_ title: String, label: String,
                                mask: InteractiveModifierMask) -> some View {
        let selected = modifiers.contains(mask)
        return Button {
            if selected { modifiers.remove(mask) }
            else { modifiers.insert(mask) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Color.black : Color.white)
                .background(selected ? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Armed for next key" : "Off")
        .accessibilityIdentifier("Remote modifier \(label.lowercased())")
        .disabled(disabled)
    }
}
#endif
