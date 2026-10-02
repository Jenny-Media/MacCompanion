import Foundation
import Security
import UIKit
import CompanionClient
import CompanionClientPlatform
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionMoonlightEngine

extension NativeLaunchFailure: ClientCommandFailurePresentingV0 {
    var commandFailureDetail: String {
        switch self {
        case .invalidRoute: "The Mac’s connected address could not be used for video. Reconnect and try Remote Control again."
        case .invalidResponse: "The Mac’s video service returned an invalid response. Stop the failed session and retry Remote Control."
        case .invalidMaterial: "Video security material could not be prepared. Stop the failed session and retry Remote Control."
        case .unavailable: "The video session ended during preparation. Reconnect and try Remote Control again."
        }
    }
}

/// OpenSSL identity/socket synchronization is inside the Objective-C owner.
private final class NativeTLSBox: @unchecked Sendable {
    let value: CompanionNativeTLS
    private let lock = NSLock()
    private var pending: (UUID, Task<Data, Error>)?
    private var closed = false
    init() throws { value = try CompanionNativeTLS.create() }
    private func reserve(_ path: String) throws -> (UUID, Task<Data, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, pending == nil else { throw NativeLaunchFailure.unavailable }
        let token = UUID(), value = self.value
        let task = Task.detached { try autoreleasepool { try value.requestPath(path) } }
        pending = (token, task)
        return (token, task)
    }
    private func finish(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        if pending?.0 == token { pending = nil }
    }
    func request(_ path: String) async throws -> Data {
        let (token, task) = try reserve(path)
        defer { finish(token) }
        return try await task.value
    }
    private func fence() -> Task<Data, Error>? {
        lock.lock(); defer { lock.unlock() }
        closed = true; value.retire()
        return pending?.1
    }
    func close() async { _ = try? await fence()?.value }
}

/// Production adapter for the authenticated native preparation seam.
/// The trusted caller supplies the exact selected primary's measured IP route.
@available(iOS 26.0, *)
@MainActor
public final class MoonlightNativeLaunchAdapterV0: UIKitClientNativeVideoPreparingV0 {
    public typealias RouteReader = @Sendable (Data) async throws -> String?
    private let signer: any ClientSessionAuthenticationSigningV0
    private let route: RouteReader
    private let diagnostic: @MainActor (String) -> Void
    private var tls: NativeTLSBox?
    private var creation: Task<NativeTLSBox, Error>?
    private var roles: NetworkClientInteractiveRoleProductBindingV0?
    private var driver: MoonlightNativeVideoDriverV0?
    private var binding: InteractiveNativeVideoBindingV0?
    private var key: NSMutableData?
    private var closed = false
    private var started = false
    private var monitor: Task<Void, Never>?
    private var drain: Task<Void, Never>?

    public init(signer: any ClientSessionAuthenticationSigningV0, verifiedPrimaryRoute: @escaping RouteReader,
         diagnostic: @escaping @MainActor (String) -> Void = {
             IOSClientRuntimeDiagnosticLogV0.record("native.launch." + $0)
         }) {
        self.signer = signer; route = verifiedPrimaryRoute; self.diagnostic = diagnostic
    }

    public func prepare(descriptor: AdaptiveSurfaceDescriptor, roles: NetworkClientInteractiveRoleProductBindingV0) async throws -> UIKitClientNativeVideoPreparationV0 {
        guard !closed, !started else { throw NativeLaunchFailure.unavailable }
        started = true; self.roles = roles
        do {
            diagnostic("identity")
            let creation = Task.detached { try NativeTLSBox() }; self.creation = creation
            let identity = try await creation.value
            guard !closed, !Task.isCancelled else { await identity.close(); throw NativeLaunchFailure.unavailable }
            tls = identity; self.creation = nil
            guard let der = identity.value.certificateDER else { throw NativeLaunchFailure.invalidMaterial }
            if case .active = await roles.state { diagnostic("enrollment-active") }
            else { diagnostic("enrollment-inactive") }
            let enrolled = try await roles.enrollNativeVideo(descriptor: descriptor, clientCertificateDER: der, signer: signer,
                validateCertificate: { data in
                    // The existing attestation validator accepts either purpose;
                    // the adapter checks the specific host purpose again below.
                    CompanionNativeTLS.validateCertificateDER(data, server: false) || CompanionNativeTLS.validateCertificateDER(data, server: true)
                })
            binding = enrolled.authority.binding
            diagnostic("enrolled")
            try await check()
            guard let address = try await route(enrolled.authority.binding.primaryConnectionID) else { throw NativeLaunchFailure.invalidRoute }
            try await check()
            _ = try identity.value.bindAddress(address, portBase: enrolled.portBase, hostCertificateDER: enrolled.hostCertificateDER)
            diagnostic("route-bound")
            let info = try NativeLaunchXML.parse(await identity.request("/serverinfo?uniqueid=" + descriptor.interactiveSessionID.uuidString))
            try await check()
            guard info.fields["PairStatus"] == "1", let version = info.fields["appversion"], NativeLaunchValidationV0.validVersion(version),
                  let codecText = info.fields["ServerCodecModeSupport"], let codecs = UInt32(codecText), codecs != 0 else { throw NativeLaunchFailure.invalidResponse }
            diagnostic("server-info-valid")
            let list = try NativeLaunchXML.parse(await identity.request("/applist?uniqueid=" + descriptor.interactiveSessionID.uuidString))
            try await check()
            guard list.apps.count == 1, list.apps[0]["AppTitle"] == "Desktop", let id = list.apps[0]["ID"],
                  let appID = UInt32(id), appID > 0 else { throw NativeLaunchFailure.invalidResponse }
            diagnostic("app-list-valid")
            let material = NSMutableData(length: 16)!
            guard SecRandomCopyBytes(kSecRandomDefault, 16, material.mutableBytes) == errSecSuccess else { throw NativeLaunchFailure.invalidMaterial }
            key = material
            var keyID: UInt32 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout.size(ofValue: keyID), &keyID) == errSecSuccess else { throw NativeLaunchFailure.invalidMaterial }
            let hex = (material as Data).map { String(format: "%02x", $0) }.joined()
            let path = "/launch?uniqueid=\(descriptor.interactiveSessionID.uuidString)&appid=\(appID)&mode=\(descriptor.encodedWidth)x\(descriptor.encodedHeight)x60&additionalStates=1&sops=0&rikey=\(hex)&rikeyid=\(Int32(bitPattern: keyID))&localAudioPlayMode=0&surroundAudioInfo=196610&remoteControllersBitmap=0&gcmap=0&gcpersist=0&corever=1"
            let launched = try NativeLaunchXML.parse(await identity.request(path))
            try await check()
            guard launched.fields["gamesession"] == "1", let sessionURL = launched.fields["sessionUrl0"],
                  NativeLaunchValidationV0.validStreamURL(sessionURL, address: address, port: Int(enrolled.portBase) + 21),
                  try await route(enrolled.authority.binding.primaryConnectionID) == address else { throw NativeLaunchFailure.invalidRoute }
            diagnostic("launch-response-valid")
            try await check()
            let config = CompanionMoonlightVideoConfiguration()
            config.host = address; config.appVersion = version; config.serverCodecModeSupport = codecs
            config.sessionURL = sessionURL; config.streamKey = material as Data; config.streamKeyID = keyID
            config.width = Int32(descriptor.encodedWidth); config.height = Int32(descriptor.encodedHeight)
            config.framesPerSecond = 60; config.bitrateKbps = 10_000
            let driver = MoonlightNativeVideoDriverV0(configuration: config, retired: { [weak self] in
                Task { await self?.close() }
            }, diagnostic: { [weak self] event in
                self?.diagnostic(event)
            }); self.driver = driver
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, let self else { return }
                    do { try await self.check() } catch { await self.close(); return }
                }
            }
            return .init(binding: enrolled.authority.binding, driver: driver,
                current: { [weak self] in self?.closed == false ? self?.binding : nil },
                acknowledgePresentation: { [weak self] generation, surface in
                    guard let self, let generation = Int64(exactly: generation) else { throw NativeLaunchFailure.unavailable }
                    try await self.check()
                    self.diagnostic("presentation-request")
                    let receipt: InteractiveNativeVideoPresentationReceiptBodyV0
                    do {
                        receipt = try await roles.acknowledgeNativePresentation(nativeGeneration: generation,
                            encodedWidth: UInt16(surface.encodedWidth), encodedHeight: UInt16(surface.encodedHeight))
                    } catch {
                        if let failure = error as? ClientInteractivePrimaryChannelErrorV0 {
                            self.diagnostic("presentation-failed-primary-" + String(describing: failure))
                        } else {
                            self.diagnostic("presentation-failed-" + String(reflecting: type(of: error)))
                        }
                        throw error
                    }
                    try await self.check()
                    self.diagnostic(receipt.inputAdmitted ? "presentation-input-admitted" : "presentation-acknowledged")
                    return receipt
                })
        } catch {
            if let failure = error as? NativeLaunchFailure {
                diagnostic("failed-" + String(describing: failure))
            } else {
                diagnostic("failed-" + String(reflecting: type(of: error)))
            }
            await close(); throw error
        }
    }
    private func check() async throws {
        guard !closed, !Task.isCancelled, let roles, await roles.isNativeVideoEnrollmentCurrent(), !closed,
              let binding, DispatchTime.now().uptimeNanoseconds / 1_000_000 < binding.expiresAtMonotonicMilliseconds else { throw NativeLaunchFailure.unavailable }
    }
    public func close() async {
        if let drain { await drain.value; return }
        closed = true; binding = nil; monitor?.cancel(); monitor = nil
        creation?.cancel(); tls?.value.retire()
        let tls = self.tls, pending = creation, driver = self.driver, roles = self.roles, key = self.key
        self.tls = nil; creation = nil; self.driver = nil; self.roles = nil; self.key = nil
        let task = Task {
            await driver?.stop()
            await roles?.stopNativeVideoEnrollment()
            if let pending, let late = try? await pending.value { await late.close() }
            await tls?.close()
            key?.resetBytes(in: NSRange(location: 0, length: key?.length ?? 0))
        }
        drain = task; await task.value
    }
}
