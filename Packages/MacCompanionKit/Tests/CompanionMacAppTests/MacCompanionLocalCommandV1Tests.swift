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

    for value in [
        "https://open",
        "maccompanion://enable",
        "maccompanion://disable",
        "maccompanion://open/path",
        "maccompanion://open?command=disable",
        "maccompanion://repair-agent-registration#again",
        "maccompanion://user@open",
    ] {
        let url = try #require(URL(string: value))
        #expect(MacCompanionLocalCommandV1(url: url) == nil)
    }
}
