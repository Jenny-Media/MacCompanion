# VNC prototype

Disposable iOS desktop viewer for evaluating macOS Screen Sharing (RFB/VNC).
This experiment is not linked into either Mac Companion release target.

## Scope

- One upstream LibVNCClient connection owns framebuffer updates and ordered input.
- Display choices and pinch/pan operate on the existing framebuffer locally.
- Framebuffer resize is handled inside the same connection.
- Native iOS keyboard, Escape, Tab, modifier keys, arrows, and pointer input.
  Pointer, Drag, and Pan modes share a single input queue. Button transitions
  are retained while consecutive pointer motion can be coalesced.
- Backgrounding stops the worker and releases held keys/buttons. Foregrounding
  reconnects through the same serial owner, using credentials still in memory.
- Manual Disconnect clears the password field. Credentials are never persisted
  by the prototype. The app writes numeric counters only.

Application/window isolation, audio, clipboard, WAN connectivity, production
pairing, and performance optimization are outside this first comparison.
App selection in a later VNC product would initially focus a window or crop the
desktop; VNC does not provide isolated per-window capture by itself.

## Authentication and transport

Enable macOS Screen Sharing through System Settings if it is not already on.
Enter the Mac account username/password directly in the viewer. Real builds
accept upstream Apple Remote Desktop authentication only. No Mac Companion
authentication, grant, signature, or pairing semantics are changed.

This build accepts private/loopback IPv4 destinations only. ARD authentication
does **not** make the subsequent framebuffer and input stream end-to-end
encrypted. Use the prototype on a trusted LAN. A production replacement needs
an authenticated encrypted tunnel and a design that preserves pair-once use.

The pinned GPL-2.0-or-later library and source-built OpenSSL inputs are recorded
in `source-lock.json`. OpenSSL is checked against its SDK-specific provenance.
No Homebrew macOS runtime library may be linked into the iOS application.
The initial baseline uses ZRLE/zlib/hextile/raw, with JPEG/Tight omitted; this
limits conclusions about achievable VNC bandwidth and frame rate.

## Build

Fetch the exact upstream tag into a private temporary directory:

```sh
git clone --depth 1 --branch LibVNCServer-0.9.15 https://github.com/LibVNC/libvncserver.git /private/tmp/vnc-source
python3 Experiments/VNCPrototype/build.py \
  --source /private/tmp/vnc-source \
  --openssl /private/tmp/source-built-openssl \
  --output /private/tmp/vnc-prototype-sim \
  --sdk iphonesimulator
```

The OpenSSL directory must contain SDK-specific frameworks and provenance from
the existing source builder. Generated Xcode projects, build inputs, optional
display geometry, signing material, and installed artifacts stay outside Git.
Use `iphoneos` for a separately signed physical build. Bundle identity is
disposable (`dev.maccompanion.vnc-prototype`); existing pairing/Keychain groups
are not used. Display name is **VNC Prototype**.

`--display-layout` optionally embeds private generated normalized Mac display
geometry. The viewer exposes those display crops only when the desktop's aspect
ratio matches that layout. Without a match, use All Displays and pinch/pan.
Bonjour currently prefills the first responding Screen Sharing host; with
several Macs on the network, confirm that host before entering the account.

## Verify

Run the generated synthetic peer on loopback:

```sh
python3 Experiments/VNCPrototype/synthetic_server.py --metrics /private/tmp/vnc-metrics.json
```

Launch a Simulator build with `--fixture --exercise`. Only a Simulator binary
can accept the no-auth loopback fixture. The exercise sends synthetic input and
changes the local viewport 50 times while the server resizes the framebuffer
twice. Check server/client counters for one connection, continuing frames,
balanced key down/up events, and released buttons. No pixels or typed content
are stored. Also check disconnect/reconnect and background recovery.

The generated Xcode scheme includes `VNCLifecycleTests`. It uses a synthetic
desktop to verify ten menu view choices keep the original connection, the
onscreen keyboard sends events, and actual OS background/foreground creates
exactly one replacement connection followed by a clean manual disconnect.
`--probe-mac` in a Simulator build stops at the ARD credential callback without
sending a username or password. Diagnostic counters classify constant upstream
failure formats; they never render or record server-supplied error text.

For physical acceptance, enter the account directly on iPhone and test repeated
display changes, Mac Space changes, window resizing, input, and background /
foreground. Record connection counts and actual outcomes separately from the
synthetic test. Successful build/install is not physical acceptance.
