#if os(iOS)
@testable import CompanionClientUI
import CompanionInteractiveWire
import Testing

@available(iOS 17.0, *)
@Test func remoteShortcutCatalogExposesRequiredQuickActions() {
    #expect(ClientRemoteShortcutCatalogV0.quick.map(\.id) == [
        "app-next", "tab-next", "select-all", "copy", "paste",
        "screenshot-selection",
    ])
}

@available(iOS 17.0, *)
@Test func remoteShortcutCatalogUsesMacKeyboardChords() {
    #expect(ClientRemoteShortcutCatalogV0.appNext.usage == 0x2b)
    #expect(
        ClientRemoteShortcutCatalogV0.appNext.modifiers
            == [.leftCommand]
    )
    #expect(
        ClientRemoteShortcutCatalogV0.tabPrevious.modifiers
            == [.leftControl, .leftShift]
    )
    #expect(ClientRemoteShortcutCatalogV0.windowNext.usage == 0x35)
    #expect(ClientRemoteShortcutCatalogV0.screenshotFull.usage == 0x20)
    #expect(ClientRemoteShortcutCatalogV0.screenshotSelection.usage == 0x21)
    #expect(ClientRemoteShortcutCatalogV0.screenshotOptions.usage == 0x22)
}
#endif
