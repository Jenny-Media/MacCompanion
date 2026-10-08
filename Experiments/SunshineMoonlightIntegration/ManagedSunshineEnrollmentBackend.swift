#if os(macOS)
import CompanionMacApplicationPlatform

// Experimental callers use the production implementation.
typealias ManagedSunshineEnrollmentBackend = MacManagedSunshineEnrollmentBackendV1
#endif
