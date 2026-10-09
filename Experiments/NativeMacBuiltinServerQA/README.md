# Disposable native Mac live-server QA

`SSHProbe.swift` is an opt-in command-line experiment using the same pinned
Citadel transport and paused-read admission as the direct client. Generate its
temporary Xcode project and products outside Git; never add it to a release
target. Provide only a disposable, authorized VM through `MC_VM_HOST`,
`MC_VM_ACCOUNT`, `MC_VM_PASSWORD` and `MC_VM_HOST_KEY`. Obtain the public host
fingerprint independently from the VM console before connecting. Run with an
external timeout. The probe prints results without passwords or shell content.
`run_ssh_probe.py --build /private/tmp/maccompanion-direct-macos --output
/private/tmp/maccompanion-live-ssh-probe` validates and stages the existing
dependencies, generates that isolated project and runs with a 60-second timeout.
Use the stable Xcode `DEVELOPER_DIR`, and run it separately from native QA because
they share temporary build products. It does not register an Apple app identity.

It checks two connections to built-in Remote Login, closure isolation, PTY
input/output and resize. It does not verify native window focus, application
Keychain persistence or iCloud delivery. VM disks and test logs stay outside Git.
