# Network discovery construction evidence — 2026-08-20

Status: passed as an identity-neutral, no-network-activity compile/construction probe. This is not Local Network permission, advertisement, browse, resolution, TLS pinning, or physical-device evidence.

Environment:

- macOS host using the installed Xcode 27 beta toolchain
- disposable `Experiments/NetworkDiscoveryProbe` executable
- no permanent bundle identifier, signing identity, entitlement, or `NSBonjourServices` declaration

The probe maps the closed `CompanionDiscovery` profile to Network.framework `NWListener.Service`, `NWTXTRecord`, `NWBrowser.Descriptor.bonjour`, and `NWEndpoint.service`. It cancels the unstarted browser and never starts a listener or browser.

Observed default result:

```json
{
  "candidate" : "mac-018f._maccompanion._tcp.local.",
  "domain" : "local.",
  "experimentOnly" : true,
  "serviceType" : "_maccompanion._tcp",
  "startedNetworkActivity" : false
}
```

This proves only that the intended service/profile mapping compiles against the currently available SDK and can be constructed without network activity. Stable-Xcode compilation and signed physical Mac/iPhone tests must separately prove Local Network grant, denial, Settings recovery, TXT parsing, advertisement/browse/resolve, interface changes, and responsible-code attribution.
