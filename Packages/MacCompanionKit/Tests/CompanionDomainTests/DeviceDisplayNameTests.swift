import CompanionDomain
import Foundation
import Testing

@Test func deviceDisplayNameAcceptsBoundedCanonicalLocalPresentationText() throws {
    let value = try DeviceDisplayName("Jenny’s iPhone 📱")
    #expect(value.rawValue == "Jenny’s iPhone 📱")
    let encoded = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(DeviceDisplayName.self, from: encoded) == value)
}

@Test func deviceDisplayNameRejectsEmptyWhitespaceAndOversizedText() {
    #expect(throws: DeviceDisplayNameError.empty) {
        try DeviceDisplayName("")
    }
    #expect(throws: DeviceDisplayNameError.surroundingWhitespace) {
        try DeviceDisplayName(" iPhone")
    }
    #expect(throws: DeviceDisplayNameError.surroundingWhitespace) {
        try DeviceDisplayName("iPhone\n")
    }
    #expect(throws: DeviceDisplayNameError.tooLong) {
        try DeviceDisplayName(String(repeating: "a", count: 65))
    }
}

@Test func deviceDisplayNameRejectsAmbiguousUnicodeAndControlScalars() {
    #expect(throws: DeviceDisplayNameError.nonCanonicalUnicode) {
        try DeviceDisplayName("Cafe\u{301}")
    }
    #expect(throws: DeviceDisplayNameError.forbiddenScalar) {
        try DeviceDisplayName("Trusted\u{202e}Phone")
    }
    #expect(throws: DeviceDisplayNameError.forbiddenScalar) {
        try DeviceDisplayName("Phone\u{0007}")
    }
}
