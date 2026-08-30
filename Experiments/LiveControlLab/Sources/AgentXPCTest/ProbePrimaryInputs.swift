#if !DEBUG || !os(macOS)
#error("Disposable primary startup inputs are macOS Debug only")
#endif
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionHost
@testable import CompanionHostPlatform
import CompanionLifecycle
import CompanionNativeProviders
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Security

/// Platform substitutes for the signed-process primary-root checkpoint. All
/// files live beneath the runner-created 0700 UUID directory, never Keychain.
enum ProbePrimaryInputs {
    enum Failure: Error { case unsafeKeyFile, missingEstablishedKey, keyCreation }

    static func make(storage: MacAgentReleaseStorageV1, state: ProductLifecycleState, store: SQLiteSecurityStore, pauseAudioResult: Bool = false)
        async throws -> (SecurityHostIdentityStartupResultV0, AgentNetworkPrimaryStartupInputsV1)
    {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let existing = try await store.hostIdentity()
        let keyURL = storage.paths.root.appendingPathComponent("isolated-software-key.bin")
        let key: P256.Signing.PrivateKey
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw Failure.unsafeKeyFile
            }
            key = try P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
        } else {
            guard existing == nil else { throw Failure.missingEstablishedKey }
            key = P256.Signing.PrivateKey()
            try key.rawRepresentation.write(to: keyURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(key.x963Representation as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
             kSecAttrKeySizeInBits: 256] as CFDictionary, &error) else {
            _ = error?.takeRetainedValue()
            throw Failure.keyCreation
        }
        let issued: SecurityHostIssuedIdentityV0
        let record: StoredHostIdentityRecord
        if let existing {
            issued = try SecurityHostIdentityKeyCustodyV0.assembleLoadedIdentity(
                privateKey: secKey, applicationTag: existing.keyApplicationTag,
                certificateDER: existing.certificateDER, wallNowUnixMilliseconds: now)
            guard issued.key.hostFingerprint == existing.hostFingerprint else {
                throw Failure.unsafeKeyFile
            }
            record = existing
            // Marker contains no key, fingerprint, certificate or host ID.
            FileHandle.standardOutput.write(Data("primary-identity-reloaded\n".utf8))
        } else {
            issued = try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(
                privateKey: secKey, applicationTag: Data("dev.maccompanion.xpc-test.ephemeral".utf8),
                serialNumber: withUnsafeBytes(of: UUID().uuid) { Data($0) },
                issuanceTimeUnixMilliseconds: now)
            record = try StoredHostIdentityRecord(hostID: UUID(), keyApplicationTag: issued.key.applicationTag,
                hostFingerprint: issued.key.hostFingerprint, certificateDER: issued.certificateDER,
                certificateNotBeforeUnixMilliseconds: issued.validity.notBeforeUnixMilliseconds,
                certificateNotAfterUnixMilliseconds: issued.validity.notAfterUnixMilliseconds,
                establishedAtUnixMilliseconds: now, updatedAtUnixMilliseconds: now)
            try await store.establishHostIdentity(record)
            FileHandle.standardOutput.write(Data("primary-identity-established\n".utf8))
        }
        let native = NativeAudioMuteProviderV1(controller: ProbeAudioMuteController())
        let provider: any CapabilityProviderV1 = pauseAudioResult
            ? ProbePausedAudioProvider(native: native, directory: storage.paths.root) : native
        return (.ready(record: record, issuedIdentity: issued, renewalRecommended: false),
            AgentNetworkPrimaryStartupInputsV1(
                registry: try CapabilityRegistrySnapshotV1(generation: UUID(), capabilities: [NativeAudioMuteCapabilityV1.descriptor()]),
                providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: [provider]),
                wallNowUnixMilliseconds: now, lifecycleState: state,
                statusPlatform: AgentHostStatusPlatformServicesV1(
                    sampler: MacSystemStatusSampler(), clock: SystemHostStatusClock(), initialGeneration: UUID()),
                interactivePlatform: .deferredMenuBinding(materials: SecurityInteractiveSessionMaterialGeneratorV0())))
    }
}

/// Calls the real native provider against the test controller, then pauses only
/// result delivery. A crash here means an effect occurred but no terminal commit.
private struct ProbePausedAudioProvider: CapabilityProviderV1 {
    let native: NativeAudioMuteProviderV1
    let directory: URL
    var identity: CapabilityProviderIdentityV1 { native.identity }
    func execute(_ request: CapabilityProviderRequestV1) async -> CapabilityProviderOutcomeV1 {
        let outcome = await native.execute(request)
        do {
            let marker = directory.appendingPathComponent("audio-effect-reached")
            try Data().write(to: marker, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            FileHandle.standardOutput.write(Data("isolated-audio-effect-paused\n".utf8))
            let deadline = ContinuousClock.now + .seconds(12)
            while ContinuousClock.now < deadline {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio-effect-release").path) {
                    return outcome
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {}
        return .outcomeUnknown
    }
    func requestCancellation(operationID: UUID) async -> Bool {
        FileHandle.standardOutput.write(Data("isolated-audio-cancellation-requested\n".utf8))
        return await native.requestCancellation(operationID: operationID)
    }
}

/// In-memory read-back fault injection; never touches CoreAudio or system mute.
private final class ProbeAudioMuteController: DefaultOutputMuteControllingV1, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool {
        lock.withLock {
            calls += 1
            FileHandle.standardOutput.write(Data("isolated-audio-execution:\(calls)\n".utf8))
            // Exactly the second execution returns a mismatching read-back.
            return calls == 2 ? !desired : desired
        }
    }
}
