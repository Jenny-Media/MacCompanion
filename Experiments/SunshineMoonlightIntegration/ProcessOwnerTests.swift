import Foundation

typealias SunshineProcessOwner = MacManagedSunshineProcessOwnerV1

@MainActor
private final class Admission {
    var allowed = true
    var exits: [Int32] = []
}

@main
private struct ProcessOwnerTests {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let supervisor = directory.appendingPathComponent("supervisor")
        let executable = directory.appendingPathComponent("fake-host")
        let configuration = directory.appendingPathComponent("configuration")
        let log = directory.appendingPathComponent("process.log")
        try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try Data().write(to: configuration)
        try Data().write(to: log)

        func owner(_ admission: Admission) -> SunshineProcessOwner {
            SunshineProcessOwner(revalidateControl: { admission.allowed }, didExit: { admission.exits.append($0) })
        }
        func start(_ process: SunshineProcessOwner, deadline: UInt64) throws {
            try process.start(supervisor: supervisor, sunshine: executable, configuration: configuration,
                dataDirectory: directory, log: log, expiresAtMonotonicNanoseconds: deadline)
        }
        func awaitExit(_ admission: Admission) async {
            for _ in 0..<100 {
                if !admission.exits.isEmpty { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure("Owned host did not exit within the bounded test")
        }

        let denied = Admission()
        denied.allowed = false
        do {
            try start(owner(denied), deadline: DispatchTime.now().uptimeNanoseconds + 5_000_000_000)
            preconditionFailure("Denied Control started a host")
        } catch SunshineProcessOwner.Failure.authorizationLost { }
        precondition(denied.exits.isEmpty)

        let expired = Admission()
        do {
            try start(owner(expired), deadline: DispatchTime.now().uptimeNanoseconds - 1)
            preconditionFailure("Expired Control started a host")
        } catch SunshineProcessOwner.Failure.leaseExpired { }
        precondition(expired.exits.isEmpty)

        let tooLong = Admission()
        do {
            try start(owner(tooLong), deadline: DispatchTime.now().uptimeNanoseconds + 14_401_000_000_000)
            preconditionFailure("Control longer than four hours started a host")
        } catch SunshineProcessOwner.Failure.leaseExpired { }
        precondition(tooLong.exits.isEmpty)

        let revoked = Admission()
        let revokedOwner = owner(revoked)
        try start(revokedOwner, deadline: DispatchTime.now().uptimeNanoseconds + 5_000_000_000)
        try await Task.sleep(for: .milliseconds(100))
        revoked.allowed = false
        await awaitExit(revoked)
        await revokedOwner.stop()
        precondition(revoked.exits == [143], "Revocation must terminate and report one reaped host")
        do {
            try start(revokedOwner, deadline: DispatchTime.now().uptimeNanoseconds + 5_000_000_000)
            preconditionFailure("Retired owner restarted")
        } catch SunshineProcessOwner.Failure.invalidPhase { }

        let stopped = Admission()
        let stoppedOwner = owner(stopped)
        try start(stoppedOwner, deadline: DispatchTime.now().uptimeNanoseconds + 14_400_000_000_000)
        try await Task.sleep(for: .milliseconds(100))
        precondition(stoppedOwner.isRunning && stopped.exits.isEmpty, "Four-hour Control must survive supervisor admission")
        async let first: Void = stoppedOwner.stop()
        async let second: Void = stoppedOwner.stop()
        _ = await (first, second)
        precondition(stopped.exits.count == 1, "Concurrent Stop must report a single reaped host")
        print("Process owner checks passed: denied/expired/overlong admission, four-hour host startup, live revocation, terminal owner, concurrent Stop")
    }
}
