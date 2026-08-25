import CompanionMacApp
import Foundation
import Testing

@Test
func localCommandAcceptsOnlyExactNarrowURLs() throws {
    #expect(
        MacCompanionLocalCommandV1(
            url: try #require(URL(string: "maccompanion://open"))
        ) == .openWindow
    )
    #expect(
        MacCompanionLocalCommandV1(
            url: try #require(
                URL(string: "maccompanion://repair-agent-registration")
            )
        ) == .repairAgentRegistration
    )
    #expect(
        MacCompanionLocalCommandV1(
            url: try #require(
                URL(string: "maccompanion://allow-remote-control")
            )
        ) == .reviewInteractiveControlGrant
    )

    for value in [
        "https://open",
        "maccompanion://enable",
        "maccompanion://disable",
        "maccompanion://open/path",
        "maccompanion://open?command=disable",
        "maccompanion://repair-agent-registration#again",
        "maccompanion://allow-remote-control?approve=true",
        "maccompanion://allow-remote-control/approve",
        "maccompanion://user@open",
    ] {
        let url = try #require(URL(string: value))
        #expect(MacCompanionLocalCommandV1(url: url) == nil)
    }
}
