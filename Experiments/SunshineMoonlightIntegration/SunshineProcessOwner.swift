#if os(macOS)
import CompanionMacApplicationPlatform

// Experimental callers use the production implementation.
typealias SunshineProcessOwner = MacManagedSunshineProcessOwnerV1
#endif
