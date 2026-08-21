import Foundation

public enum FixturePaths {
    public static func repositoryRoot(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent() // CompanionTestSupport
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // MacCompanionKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root parent correction
    }

    public static func authoritativeFixtures(filePath: StaticString = #filePath) -> URL {
        repositoryRoot(filePath: filePath)
            .appendingPathComponent("spec/fixtures", isDirectory: true)
    }
}
