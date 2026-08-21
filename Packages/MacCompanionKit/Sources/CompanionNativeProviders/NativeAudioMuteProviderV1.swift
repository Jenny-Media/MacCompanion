import CompanionDomain
import CompanionOperations
import CompanionWire
import Foundation

#if os(macOS)
import CoreAudio
#endif

public enum NativeAudioMuteCapabilityV1 {
    public static let capabilityID = "maccompanion.system.setAudioMuted"
    public static let providerID = "maccompanion.native.audio"
    public static let providerVersion = "1.0.0"
    public static let providerGeneration = UUID(
        uuidString: "018f8300-0000-7000-8000-000000000001"
    )!
    public static let executionRevision = UUID(
        uuidString: "018f8400-0000-7000-8000-000000000001"
    )!

    public static func descriptor() throws -> CapabilityDescriptorV1 {
        let muted = try CapabilitySchemaPropertyV1(
            name: "muted",
            required: true,
            schema: .boolean()
        )
        return try CapabilityDescriptorV1(
            capabilityID: capabilityID,
            schemaVersion: 1,
            providerID: providerID,
            providerVersion: providerVersion,
            providerGeneration: providerGeneration,
            executionRevision: executionRevision,
            englishTitle: "Set audio mute",
            englishSummary: "Set the default audio output to muted or unmuted.",
            parameterSchema: .object(properties: [muted]),
            resultSchema: .object(properties: [muted]),
            effects: CapabilityEffectFacts(
                dataAccess: .none,
                changesLocalState: .reversible,
                mayDisruptUser: false,
                invokesExternalService: false,
                usesCredentials: false,
                destructive: false,
                requiresForegroundSession: false,
                allowedWhileLocked: false,
                cancellation: .notApplicable
            )
        )
    }
}

public enum DefaultOutputMuteErrorV1: Error, Equatable, Sendable {
    case unavailable
    case rejected
    case executionFailed
}

public protocol DefaultOutputMuteControllingV1: Sendable {
    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool
}

public struct NativeAudioMuteProviderV1: CapabilityProviderV1 {
    public let identity: CapabilityProviderIdentityV1
    private let controller: any DefaultOutputMuteControllingV1

    public init(controller: any DefaultOutputMuteControllingV1) {
        identity = CapabilityProviderIdentityV1(
            providerID: NativeAudioMuteCapabilityV1.providerID,
            providerVersion: NativeAudioMuteCapabilityV1.providerVersion,
            providerGeneration: NativeAudioMuteCapabilityV1.providerGeneration,
            executionRevision: NativeAudioMuteCapabilityV1.executionRevision
        )
        self.controller = controller
    }

    public func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        guard request.capabilityID == NativeAudioMuteCapabilityV1.capabilityID,
              case let .object(members) = request.parameters,
              members.count == 1,
              members[0].key == "muted",
              case let .boolean(desired) = members[0].value else {
            return .failed(.rejected)
        }
        do {
            let verified = try controller.setDefaultOutputMuted(desired)
            guard verified == desired else { return .failed(.rejected) }
            return .succeeded(
                resultJSON: Data("{\"muted\":\(verified ? "true" : "false")}".utf8)
            )
        } catch DefaultOutputMuteErrorV1.unavailable {
            return .failed(.unavailable)
        } catch DefaultOutputMuteErrorV1.rejected {
            return .failed(.rejected)
        } catch {
            return .failed(.executionFailed)
        }
    }
}

#if os(macOS)
public struct CoreAudioDefaultOutputMuteControllerV1:
    DefaultOutputMuteControllingV1 {
    public init() {}

    public func setDefaultOutputMuted(_ desired: Bool) throws -> Bool {
        let device = try defaultOutputDevice()
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &muteAddress) else {
            throw DefaultOutputMuteErrorV1.unavailable
        }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &muteAddress, &settable)
                == noErr,
              settable.boolValue else {
            throw DefaultOutputMuteErrorV1.unavailable
        }
        let current = try readMute(device: device, address: &muteAddress)
        if current == desired { return current }

        var replacement: UInt32 = desired ? 1 : 0
        let setStatus = AudioObjectSetPropertyData(
            device,
            &muteAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &replacement
        )
        guard setStatus == noErr else {
            throw DefaultOutputMuteErrorV1.executionFailed
        }
        guard try defaultOutputDevice() == device else {
            throw DefaultOutputMuteErrorV1.unavailable
        }
        let verified = try readMute(device: device, address: &muteAddress)
        guard verified == desired else {
            throw DefaultOutputMuteErrorV1.rejected
        }
        return verified
    }

    private func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr,
              size == UInt32(MemoryLayout<AudioDeviceID>.size),
              device != kAudioObjectUnknown else {
            throw DefaultOutputMuteErrorV1.unavailable
        }
        return device
    }

    private func readMute(
        device: AudioDeviceID,
        address: inout AudioObjectPropertyAddress
    ) throws -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr,
              size == UInt32(MemoryLayout<UInt32>.size),
              value == 0 || value == 1 else {
            throw DefaultOutputMuteErrorV1.executionFailed
        }
        return value == 1
    }
}
#endif
