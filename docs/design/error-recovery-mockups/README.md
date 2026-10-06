# Error and recovery design prototype

Design proposal only. All Macs, accounts, addresses, terminal output and
fingerprints are synthetic. Actions have no network, storage, clipboard,
credential, purchase or remote-command effects.

Serve docs/design with a localhost static server, then open
/error-recovery-mockups/index.html. The current review server is:

http://127.0.0.1:4184/error-recovery-mockups/index.html

Use the scenario selector to inspect 29 states. The review controls toggle
light/dark appearance and larger text. The overview link shows key rejection,
Mac Settings and key installation together. Longer phone content scrolls.

The source audit and message inventory are one directory above. Neither is a
runtime message catalog or protocol fixture. Native implementation follows
design review, typed failure classification and the existing security gates.
