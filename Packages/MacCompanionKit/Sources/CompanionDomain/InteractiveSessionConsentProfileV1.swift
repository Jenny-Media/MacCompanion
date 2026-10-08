/// Immutable product policy for the fresh, signed remote session challenge.
/// Wire callers cannot change this profile or select a fallback key.
public enum InteractiveSessionConsentProfileV1: String, Sendable {
    case freshUserPresence
    case trustedDevice
}
