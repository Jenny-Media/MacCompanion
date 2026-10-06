"use strict";

// Design-only: synthetic content and navigation. No network or storage operations.
const icons = {
  terminal: '<svg viewBox="0 0 40 40"><rect x="3" y="6" width="34" height="28" rx="5"/><path d="m11 14 6 5-6 5m11 0h7"/></svg>',
  mac: '<svg viewBox="0 0 40 40"><rect x="3" y="5" width="34" height="24" rx="3"/><path d="M20 29v6m-8 0h16"/></svg>',
  key: '<svg viewBox="0 0 40 40"><circle cx="14" cy="12" r="7"/><path d="M14 19v16l5-4-4-4 4-4-5-4"/></svg>',
  lock: '<svg viewBox="0 0 40 40"><rect x="7" y="17" width="26" height="20" rx="5"/><path d="M12 17V11a8 8 0 0 1 16 0v6m-8 8v5"/></svg>',
  cloud: '<svg viewBox="0 0 40 40"><path d="M11 29h20a7 7 0 0 0 1-14 12 12 0 0 0-23-2A8 8 0 0 0 11 29m9-14v11m-4-4 4 4 4-4"/></svg>'
};
const sceneList = [];
function add(id, group, label, title, body, points, constraint, render) {
  sceneList.push({id, group, label, title, body, points, constraint, render});
}
function go(label, scene, classes) {
  return '<button class="' + (classes || 'btn') + '" data-go="' + scene + '">' + label + '</button>';
}
function demo(label, classes) {
  return '<button class="' + (classes || 'btn') + '" data-demo>' + label + '</button>';
}
function nav(title, back, right) {
  return '<nav class="nav" aria-label="Screen navigation">' + go('Done', back || 'macs', 'pill') +
    '<div class="nav-title">' + title + '</div>' +
    (right || '<span class="placeholder" aria-hidden="true"></span>') + '</nav>';
}
function page(title, content, back, right) {
  return nav(title, back, right) + '<section class="content">' + content + '</section>';
}
function hero(icon, heading, copy) {
  return '<div class="hero-icon" aria-hidden="true">' + icons[icon] + '</div><h1>' + heading +
    '</h1><p class="subhead">' + copy + '</p>';
}
function field(label, value, error, placeholder, type) {
  return '<div class="field"><label>' + label + '<input type="' + (type || 'text') +
    '" readonly value="' + value + '" placeholder="' + (placeholder || '') + '"' +
    (error ? ' aria-invalid="true"' : '') + '></label>' +
    (error ? '<p class="field-error">' + error + '</p>' : '') + '</div>';
}
function row(label, target, extra) {
  return '<button class="row-button" data-go="' + target + '"><span class="row-label">' + label +
    '</span>' + (extra || '') + '<span class="chevron" aria-hidden="true">›</span></button>';
}
function details(rows, label) {
  return '<details><summary>' + (label || 'Connection details') + '</summary>' + rows.map(function(r) {
    return '<div class="detail-line"><span>' + r[0] + '</span><span>' + r[1] + '</span></div>';
  }).join('') + '</details>';
}
function issue(title, copy, actions, kind, detail) {
  const symbol = kind === 'success' ? '✓' : kind === 'critical' ? '!' : kind === 'neutral' ? 'ⓘ' : '!';
  return '<div class="issue ' + (kind || '') + '" role="region" aria-label="' + title +
    '"><div class="issue-top"><span class="issue-symbol" aria-hidden="true">' + symbol +
    '</span><h2>' + title + '</h2></div><p>' + copy + '</p>' +
    (actions || '') + (detail || '') + '</div>';
}
function keyCard() {
  return '<div class="key-card"><div class="key-heading"><span class="key-symbol" aria-hidden="true">' + icons.key + '</span>Travel key</div>' +
    '<p>Selected on this iPhone</p>' + go('Choose or Manage Key', 'keys', 'text-button') + '</div>';
}
function segment(key) {
  return '<div class="segment" aria-label="Login method">' + go('Password', 'password_login', key ? '' : 'active') +
    go('SSH Key', 'key_login', key ? 'active' : '') + '</div>';
}
function loginForm(key, connect) {
  return '<div class="card">' + field('Mac account', 'alex') +
    (!key ? field('Password', '', '', 'Mac account password', 'password') : '') +
    '</div>' + segment(key) + (key ? keyCard() : '') +
    (key ? go('Set Up Key on This Mac <span class="badge">PRO</span>', 'install', 'btn') : '') +
    (connect ? go(connect, 'trust_first', 'btn primary') : '') +
    '<p class="helper">Terminal uses your Mac’s built-in Remote Login (SSH). Desktop and Terminal save separate logins.</p>';
}
function terminalLogin(content, key, connect) {
  return page('Studio Mac<small>Terminal</small>',
    hero('terminal', 'Connect to Terminal', 'Sign in with a Mac account or an SSH key.') +
    content + loginForm(key, connect), 'macs', demo('•••', 'pill circle'));
}
function fingerprint(label) {
  return '<div class="fingerprint"><small>' + label + '</small><div class="mono">SHA256:ExampleFingerprintForDesignOnly00000000000</div></div>';
}
function desktopArt(inactive) {
  return '<div class="desktop-art ' + (inactive ? 'inactive' : '') +
    '" aria-label="Synthetic desktop illustration"><div class="fake-window"><div class="dots">● ● ● &nbsp; Notes</div>' +
    '<strong>Weekend ideas</strong><div class="line"></div><div class="line"></div><div class="line"></div><div class="line"></div></div></div>';
}
function desktop(extra, inactive) {
  return nav('Studio Mac', 'macs', demo('•••', 'pill circle')) +
    '<section class="desktop-canvas">' + desktopArt(inactive) + extra +
    '<div class="keyboard-bar" aria-label="Keyboard controls">⌨ &nbsp; esc &nbsp; ⇥ &nbsp; ⇧ &nbsp; ⌃ &nbsp; ⌥ &nbsp; ⌘</div></section>';
}

add('key_rejected', 'Terminal & key setup', 'SSH key rejected', 'Explain the rejection, offer setup.',
  'The current app shows a catch-all paragraph. This proposal keeps the login in place, names the rejected key and gives a useful next action.',
  ['Password login is the main recovery action.', 'Automatic setup sits beside the problem and carries a Pro badge.', 'The full fingerprint moves into details; key selection remains easy to find.'],
  'This scene assumes a confirmed SSH authentication rejection. The screenshot alone does not prove that the public key is absent. A typed failure classifier must establish rejection before this copy is used.',
  function() { return page('Studio Mac<small>Terminal</small>',
    hero('terminal', 'Connect to Terminal', 'Sign in with a Mac account or an SSH key.') +
    issue('SSH key wasn’t accepted',
    'Studio Mac didn’t accept “Travel key” for “alex”. The public key may need to be added to this account.',
    go('Use Password', 'password_login', 'btn primary') +
    go('Set Up Key on Mac <span class="badge">PRO</span>', 'install'),
    '', details([['Login method', 'SSH key'], ['Account', 'alex'], ['Result', 'Login rejected']])) +
    keyCard() + '<p class="helper">Choosing a different key doesn’t add its public key to the Mac.</p>',
    'macs', demo('•••', 'pill circle')); });

add('mac_settings', 'Terminal & key setup', 'Mac Settings', 'Give Terminal Access its own home.',
  'Key installation should be in a named setup section. Forgetting credentials and server trust belongs lower in the screen.',
  ['Account, selected key and install action are grouped together.', 'Automatic installation is visibly Pro; manual setup stays free.', 'Saving addresses remains separate from key installation.'],
  'The existing button is My Macs → ⋯ → Mac Settings → Saved Logins & Server Trust → Install Key on This Mac. This mockup proposes moving it; the native app has not changed.',
  function() { return page('Mac Settings',
    '<div class="card"><div class="account-summary"><div class="account-avatar" aria-hidden="true">▣</div><div><strong>Studio Mac</strong><small>Two connection addresses</small></div></div>' +
    row('Connection Addresses', 'validation') + '</div><p class="section-label">Terminal Access</p><div class="card">' +
    field('Mac account', 'alex') + row('SSH Key', 'keys', '<span class="row-value">Travel key</span>') +
    row('Install Public Key on Mac', 'install', '<span class="badge">PRO</span>') +
    row('Manual Key Setup', 'manual') + '</div>' +
    '<p class="helper">Choosing a key keeps it on this iPhone. Setup adds its public key to your Mac account.</p>' +
    '<p class="section-label">Saved Logins & Server Trust</p><div class="card">' +
    demo('Forget Desktop Login', 'row-button') + demo('Forget Terminal Login', 'row-button') +
    demo('Review SSH Server Key', 'row-button') + '</div><p class="helper">Removing a saved login does not remove a public key from the Mac.</p>', 'macs'); });

add('install', 'Terminal & key setup', 'Install public key', 'Make setup a short, verifiable flow.',
  'Show the target account and key before asking for a temporary login. Explain exactly what gets added.',
  ['The private key stays on the iPhone.', 'A password or working key authenticates setup; the password is not saved.', 'Fresh key-only login verifies success before setting the preferred key.'],
  'Automatic setup remains Pro or active trial. A newly seen server still requires explicit fingerprint verification. These controls simulate navigation only.',
  function() {
  return page('Set Up SSH Key', '<h1>Add your public key</h1><p class="subhead">Allow “Travel key” to sign in to Studio Mac.</p>' +
    '<div class="card">' + field('Mac account', 'alex') + field('SSH key', 'Travel key') + '</div>' +
    '<p class="section-label">Sign in once to install</p>' +
    '<div class="segment"><button class="active" data-demo>Password</button><button data-demo>Working Key</button></div>' +
    '<div class="card">' + field('Mac password', '', '', 'Password for alex', 'password') + '</div>' +
    '<p class="helper">Used only for setup. This password won’t be saved.</p>' +
    '<div class="card install-steps"><div class="step"><span class="step-dot">1</span><div>Add the public key<div class="step-note">Keep existing authorized keys.</div></div></div>' +
    '<div class="step"><span class="step-dot">2</span><div>Test key login<div class="step-note">Verify before making it preferred.</div></div></div></div>' +
    go('Install Public Key', 'installed', 'btn primary') +
    '<p class="helper">Only the public key is added to this account’s authorized_keys. Your private key stays on this iPhone.</p>', 'mac_settings');
});

add('install_uncertain', 'Terminal & key setup', 'Setup not verified', 'Treat an uncertain result honestly.',
  'A lost response or cancellation after sending setup may leave the public key installed. Repeating the command should not be the first recovery action.',
  ['Test key login before offering another installation.', 'Keep the same account, selected key and previous preferred login.', 'Explain uncertainty without suggesting setup definitely failed.'],
  'The production installer needs recorded phases: before send, sent without acknowledgment, acknowledged and verification complete. This scene represents sent without a confirmed result.',
  function() { return page('SSH Key Setup', hero('key', 'Check key login', 'Studio Mac · alex') +
    issue('Key setup wasn’t verified', 'The public key may already have been added. Your preferred login hasn’t changed.',
      go('Test Key Login', 'installed', 'btn primary') + go('Manual Setup Steps', 'manual'),
      '', details([['Setup', 'Response not confirmed'], ['Key login', 'Not verified']], 'Setup details')) +
    keyCard() + '<p class="helper">Testing login does not add the public key again.</p>', 'mac_settings'); });

add('installed', 'Terminal & key setup', 'Setup verified', 'Say success only after verification.',
  'A success screen confirms that a fresh key-only login worked and the preferred key was saved.',
  ['Short success summary instead of a long status log.', 'Offer Connect to Terminal or Done.', 'Make account ownership explicit.'],
  'A real success requires both key-only verification and durable association. This demo does not install anything.',
  function() { return page('SSH Key Setup', hero('key', 'Ready to connect', 'Studio Mac · alex') +
    issue('Public key installed', '“Travel key” signed in successfully and is now the preferred Terminal key for this Mac.',
      go('Connect to Terminal', 'terminal_connected', 'btn primary'), 'success') +
    '<div class="card install-steps"><div class="step complete"><span class="step-dot">✓</span>Public key added</div>' +
    '<div class="step complete"><span class="step-dot">✓</span>Key login verified</div>' +
    '<div class="step complete"><span class="step-dot">✓</span>Preferred key saved</div></div>' +
    '<p class="helper">Your private key remains on this iPhone.</p>', 'mac_settings'); });

add('manual', 'Terminal & key setup', 'Free manual setup', 'Keep manual setup easy to find.',
  'Users can install a public key themselves without automatic Pro setup.',
  ['Explain public versus private key.', 'Keep the target Mac account visible.', 'Link back to key login after setup.'],
  'Public-key copy/export already exists in the free app. The Copy button here shows a demo message and does not touch the clipboard.',
  function() { return page('Manual Key Setup', hero('key', 'Add a public key yourself', 'Studio Mac · alex') +
    '<div class="card install-steps"><div class="step"><span class="step-dot">1</span>Copy the public key for “Travel key”.</div>' +
    '<div class="step"><span class="step-dot">2</span>On the Mac, sign in to alex and add it to ~/.ssh/authorized_keys.</div>' +
    '<div class="step"><span class="step-dot">3</span>Return here and test key login.</div></div>' +
    demo('Copy Public Key', 'btn primary') + go('Test Key Login', 'key_login') +
    '<p class="helper">Keep existing keys. Don’t copy or upload your private key. The setup guide explains file permissions.</p>' +
    demo('Read Setup Guide', 'text-button'), 'mac_settings'); });

add('pro_setup', 'Terminal & key setup', 'Automatic setup · Pro', 'Explain access without an error alert.',
  'A Pro requirement should explain what is included and show the free alternative.',
  ['Show the entitlement before a user enters setup credentials.', 'Automatic installation is Pro; manual setup is free.', 'No key or saved host is deleted when a trial ends.'],
  'This design keeps the existing lifetime Pro and trial policy. It does not purchase, start a trial or change access.',
  function() { return page('SSH Key Setup', hero('key', 'Set up a key on your Mac', 'Choose the setup method that works for you.') +
    '<div class="card"><div class="account-summary"><div><strong>Automatic Setup</strong><small>Add the public key and verify login.</small></div><span class="badge">PRO</span></div></div>' +
    demo('View Pro Options', 'btn primary') + go('Use Free Manual Setup', 'manual') +
    '<p class="helper">Basic Desktop and Terminal remain available for free. You can copy your public key and set it up yourself.</p>', 'mac_settings'); });

add('key_login', 'Terminal & connection', 'Key login', 'Make selection and installation distinct.',
  'A normal login should have one clear connect action and setup next to the selected key.',
  ['Short key name; fingerprint in key details.', 'Set Up Key links to the target Mac, not just the local library.', 'Password remains an explicit alternative.'],
  'Selecting a local key does not mean the Mac accepts it. The UI must not display Installed without a verified result.',
  function() { return terminalLogin('', true, 'Connect with Key'); });

add('password_login', 'Terminal & connection', 'Password login', 'Keep credentials and recovery in context.',
  'Use visible field labels and a short service hint. Saved Desktop and Terminal logins stay distinct.',
  ['Keep account and login method after a failure.', 'No multiline troubleshooting paragraph ahead of the form.', 'A server identity check still appears when needed.'],
  'Fields are read-only synthetic placeholders. This mockup never receives a real password or connects to a server.',
  function() { return terminalLogin('', false, 'Connect'); });

add('ssh_unknown', 'Terminal & connection', 'Unknown connection failure', 'Avoid pretending to know the cause.',
  'When the failure phase is unknown, use honest general copy and offer settings details.',
  ['One Try Again action.', 'Keep login fields and chosen key.', 'No claim that a public key is missing or a password is wrong.'],
  'This is the appropriate fallback for the current generic terminal catch. More specific scenes require source-backed typed failures.',
  function() { return terminalLogin(issue('Couldn’t connect to Terminal', 'The connection ended before a Terminal session could open.',
    go('Try Again', 'key_login', 'btn primary') + go('Connection Settings', 'mac_settings', 'text-button'),
    '', details([['Service', 'Remote Login (SSH)'], ['Port', '22'], ['Failure stage', 'Not identified']])), true, null); });

add('password_rejected', 'Terminal & connection', 'Mac login rejected', 'Put the rejected login beside its fields.',
  'Do not call every failed authentication a wrong password. The account may also lack access.',
  ['Explain that the Mac rejected login.', 'Edit Login returns to the preserved form.', 'Put Remote Login access guidance in details.'],
  'Only show this after confirmed authentication rejection. Don’t clear or expose a stored secret.',
  function() { return terminalLogin(issue('Mac login wasn’t accepted', 'Check the account and password, and that “alex” is allowed to use Remote Login.',
    go('Edit Login', 'password_login', 'btn primary'), '', details([['Account', 'alex'], ['Result', 'Login rejected']])), false, null); });

add('network', 'Terminal & connection', 'Mac not reachable', 'Separate reachability from login.',
  'A service timeout is not proof that Remote Login is off or that the VPN is disconnected.',
  ['Name the Mac and service.', 'Retry is explicit; settings are a secondary route.', 'Bounded details show what was attempted.'],
  'Use the actual resolver or TCP result. The current dial function loses this distinction and must be changed before this scene is implemented.',
  function() { return page('Studio Mac<small>Terminal</small>', hero('terminal', 'Connect to Terminal', 'Your saved login is still available.') +
    issue('Couldn’t reach Studio Mac', 'The SSH service didn’t respond. Check that the Mac is reachable on your local network or private VPN.',
    go('Try Again', 'key_login', 'btn primary') + go('Connection Settings', 'mac_settings'),
    '', details([['Addresses tried', '2'], ['SSH port', '22'], ['Result', 'No response']])) +
    '<p class="helper">No login was sent. Check Remote Login and the SSH port if the Mac is otherwise reachable.</p>', 'macs'); });

add('desktop_disconnected', 'Session recovery', 'Desktop disconnected', 'Recover without losing the viewport.',
  'Keep the last frame visibly inactive and place recovery in a compact bottom panel.',
  ['One Reconnect action and one Done exit.', 'No full-screen flash or repeated blocking alert.', 'Remember the valid display and zoom; do not replay input.'],
  'An inactive frame is not live. Reconnecting requires a new connection; restoring viewport is conditional on compatible layout.',
  function() { return desktop('<div class="desktop-issue"><h2>Desktop disconnected</h2><p>Your display and zoom are saved. Reconnect to continue controlling Studio Mac.</p>' +
    go('Reconnect', 'desktop_connected', 'btn primary') + details([['Service', 'Screen Sharing'], ['Result', 'Connection ended']]) + '</div>', true); });

add('terminal_disconnected', 'Session recovery', 'Terminal shell closed', 'Do not promise a shell can resume.',
  'Backgrounding currently closes the SSH shell. Make that different from Desktop reconnection.',
  ['Retain context, but mark the shell closed.', 'Open New Shell is explicit.', 'Do not resend typed commands or suggest the previous shell is restored.'],
  'The direct Terminal currently closes on background. This proposal adds no persistent remote shell or background execution.',
  function() { return page('Studio Mac<small>Terminal</small>',
    issue('Terminal session ended', 'The SSH shell closed while the app was in the background. Open a new shell to continue.',
      go('Open New Shell', 'terminal_connected', 'btn primary'), 'neutral') +
    '<div class="card" style="padding:20px"><p class="mono">alex@studio-mac ~ %<br><br>Previous session · closed</p></div>' +
    '<p class="helper">The previous shell won’t be restored. Unsent input won’t be replayed.</p>', 'macs'); });

add('trust_first', 'Server identity', 'First SSH connection', 'Keep server verification explicit.',
  'A first connection needs an independent identity check before login credentials are sent.',
  ['Show the target Mac and fingerprint.', 'Explain where the fingerprint should be checked.', 'Use an explicit Trust & Connect action and a cancel route.'],
  'This is a presentation proposal only. It does not weaken or change the existing SSH trust decision. The fingerprint is synthetic.',
  function() { return page('Verify This Mac', hero('lock', 'Is this your Mac?', 'You’re connecting to Studio Mac for the first time.') +
    '<p class="subhead">Check this SSH server fingerprint independently on your Mac before trusting it.</p>' +
    fingerprint('SSH server fingerprint · Ed25519') + demo('How to Check the Fingerprint', 'text-button') +
    go('Trust & Connect', 'terminal_connected', 'btn primary') + go('Cancel', 'key_login') +
    '<p class="helper">Trust is saved for this server. No login is sent until you approve.</p>', 'key_login'); });

add('trust_changed', 'Server identity', 'SSH identity changed', 'Make an identity change a distinct warning.',
  'This warning must block login. A normal Retry card would hide the risk.',
  ['State that login has been stopped.', 'Require independent verification.', 'Do not automatically forget trust or offer a casual Trust Anyway action.'],
  'Actual stored and presented fingerprints must remain available locally. No trust reset or security behavior is changed in this mockup.',
  function() { return page('Server Identity', hero('lock', 'This Mac’s identity changed', 'Studio Mac') +
    issue('Login stopped', 'The SSH server key differs from the one you trusted. This can happen after reinstalling macOS, or if you reached a different server.',
      '', 'critical') + fingerprint('New server fingerprint · synthetic') +
    demo('How to Verify', 'btn primary') + go('Back to Macs', 'macs') +
    '<p class="helper">Keep the saved server key until you have independently verified the change.</p>', 'macs'); });

add('storage', 'Saved data & settings', 'Saved Macs unavailable', 'A failed read should not look like an empty library.',
  'The screenshot’s welcome state implies no saved Macs. Use an unavailable state and keep the original data.',
  ['Clear saved-data message at the owning screen.', 'Retry without rebuilding or replacing the file.', 'Guidance depends on whether storage is locked or unreadable.'],
  'Unlocking may solve protected-data access, but it cannot repair malformed data. Do not assert data is recovered or overwrite the original file.',
  function() { return page('My Macs', hero('mac', 'Your Macs', 'Saved connections on this iPhone') +
    issue('Saved Macs unavailable', 'The app couldn’t read your saved Macs. Your existing data has been kept.',
      demo('Retry', 'btn primary') + demo('Recovery Help', 'text-button'),
      '', details([['Data', 'Preserved'], ['Read result', 'Unavailable']], 'Storage details')) +
    '<p class="helper">Adding or changing Macs is unavailable until saved data can be read.</p>' +
    '<button class="btn" disabled>Add Mac</button>', 'macs'); });

add('validation', 'Saved data & settings', 'Field validation', 'Explain a disabled Save beside the field.',
  'An invalid port needs a precise local correction, not a generic save failure.',
  ['Leave drafts intact.', 'Show the allowed range under SSH Port.', 'Blank values use the standard service port.'],
  'Desktop and SSH ports are independent. Default Desktop port is 5900; default SSH port is 22.',
  function() { return nav('Connection Settings', 'mac_settings', '<button class="pill" disabled>Save</button>') +
    '<section class="content"><p class="section-label">Connection Addresses</p><div class="card">' +
    field('Preferred address', 'studio-mac.local') + field('Other address', 'studio-mac.example') + '</div>' +
    '<p class="section-label">Advanced</p><div class="card">' + field('Desktop port', '', '', '5900 · Default') +
    field('SSH port', '70000', 'Use a port from 1 to 65535, or leave blank for 22.') + '</div>' +
    '<p class="helper">Correct SSH Port to save. Your address and other changes are kept.</p></section>'; });

add('keys', 'Keys & privacy', 'Local SSH keys', 'Give key management a clear boundary.',
  'Manage keys on this iPhone here. Installing on a particular Mac belongs in that Mac’s Terminal Access settings.',
  ['Named key and expandable fingerprint.', 'Create/import/export stay grouped.', 'Keep an obvious route back to host setup.'],
  'This mockup uses a synthetic key name. It reads no Keychain records and has no real key material.',
  function() { return page('SSH Keys', hero('key', 'Keys on this iPhone', 'Select a key for Terminal login.') +
    '<div class="key-card"><div class="key-heading"><span class="key-symbol" aria-hidden="true">' + icons.key + '</span>Travel key <span class="badge">SELECTED</span></div>' +
    fingerprint('Public fingerprint · synthetic') + demo('Export Public Key', 'text-button') +
    go('Export Private Backup', 'export_cancelled', 'text-button') + '</div>' +
    demo('Create Key', 'btn primary') + go('Import Key', 'import_invalid') +
    go('Set Up on Studio Mac', 'mac_settings', 'text-button') +
    '<p class="helper">Selecting or importing a key doesn’t add its public key to a Mac.</p>', 'key_login'); });

add('import_invalid', 'Keys & privacy', 'Unsupported key import', 'Make import requirements specific.',
  'Give the reason next to the selected file and explain supported formats.',
  ['No generic Could Not Import alert.', 'Choose Another File is the recovery action.', 'Preserve the key library and import draft.'],
  'Current support is Ed25519 OpenSSH files up to 32 KiB, with bounded supported encryption settings. A decryption failure may also mean a damaged file.',
  function() { return page('Import SSH Key', hero('key', 'Import a private key', 'Your key will be stored on this iPhone.') +
    '<div class="card">' + field('Selected file', 'work-key.pem') + '</div>' +
    issue('This key format isn’t supported', 'Use an Ed25519 private key in OpenSSH format. RSA and ECDSA keys aren’t currently supported.',
      demo('Choose Another File', 'btn primary')) +
    '<p class="helper">Maximum file size: 32 KiB. Encrypted keys may require a passphrase. Cancelling the file picker returns here without an error.</p>', 'keys'); });

add('export_cancelled', 'Keys & privacy', 'Export cancelled', 'Cancellation is a normal outcome.',
  'A cancelled authentication prompt should not look like a broken key or a failed connection.',
  ['Neutral explanation.', 'Original key remains available.', 'Try again only if the user chooses.'],
  'Distinguish user authentication cancellation from a real export preparation or write failure.',
  function() { return page('Export Private Backup', hero('lock', 'Export cancelled', 'Your key hasn’t changed.') +
    issue('No backup was exported', 'Authentication was cancelled. “Travel key” is still available on this iPhone.',
      demo('Try Export Again', 'btn primary') + go('Back to Keys', 'keys'), 'neutral') +
    '<p class="helper">Private backups contain sensitive key material. Store exported files securely.</p>', 'keys'); });

add('app_unlock', 'Keys & privacy', 'App unlock cancelled', 'Keep content private during authentication.',
  'An opaque privacy cover protects loaded app content while authentication runs.',
  ['No host names or desktop previews before unlock.', 'Cancellation leaves the cover visible.', 'Retry uses the normal Face ID/passcode path.'],
  'The content may load beneath the privacy cover, but it must not be visible or accessible before authentication succeeds. This scene has no authentication capability.',
  function() { return '<section class="privacy-view"><div class="hero-icon" aria-hidden="true">' + icons.lock +
    '</div><h1>Unlock Mac Companion</h1><p>Use Face ID or your iPhone passcode to continue.</p>' +
    go('Unlock', 'macs', 'btn primary') + '</section>'; });

add('icloud', 'iCloud & purchases', 'iCloud Sync unavailable', 'Keep local use separate from sync trouble.',
  'An iCloud error belongs in Sync Settings. Explain local state without promising cross-device delivery.',
  ['Keep local Macs and keys.', 'Retry Sync and Sync Help are targeted actions.', 'Keep opt-in security information visible.'],
  'A Keychain submission does not prove another device received data. Keep default-off opt-in and existing privacy boundaries.',
  function() { return page('iCloud Sync', hero('cloud', 'Sync between your devices', 'Optional · Uses your iCloud account') +
    issue('iCloud Sync unavailable', 'The app couldn’t access iCloud Sync. Your local Macs and SSH keys are still available.',
      demo('Retry Sync', 'btn primary') + demo('Sync Help', 'text-button')) +
    '<div class="card"><div class="account-summary"><div><strong>Local data is kept</strong><small>Continue using this iPhone normally.</small></div></div></div>' +
    '<p class="helper">Sync relies on iCloud security to protect your data. Sync availability and delivery depend on your account and devices.</p>', 'macs'); });

add('purchase_pending', 'iCloud & purchases', 'Purchase awaiting approval', 'Pending is a state, not a failed purchase.',
  'A purchase may be waiting for approval. Avoid encouraging a second purchase.',
  ['Keep using free features.', 'Show one Done action.', 'Do not claim Apple charged or didn’t charge the account.'],
  'This is a synthetic StoreKit pending state. No purchase or entitlement check happens here.',
  function() { return page('Mac Companion Pro', hero('mac', 'Waiting for approval', 'Your purchase is pending.') +
    issue('Purchase awaiting approval', 'Apple hasn’t completed this purchase yet. Pro will unlock once a verified purchase is available.',
      go('Keep Using Free', 'macs', 'btn primary'), 'neutral') +
    '<p class="helper">You don’t need to buy again. Basic Desktop and Terminal remain available.</p>' +
    demo('Purchase Help', 'text-button'), 'macs'); });

add('purchase_uncertain', 'iCloud & purchases', 'Purchase not confirmed', 'Recover a purchase without repurchasing.',
  'An unverified purchase needs restore/history guidance. It is not proof that no transaction took place.',
  ['Restore is the main recovery action.', 'Keep previously verified access.', 'Allow free use and provide Apple purchase history guidance.'],
  'Do not change entitlements based on a presentation string or claim a refund/charge. Only verified StoreKit evidence controls access.',
  function() { return page('Mac Companion Pro', hero('mac', 'Check your Pro access', 'Your saved Macs and keys are kept.') +
    issue('Purchase couldn’t be confirmed', 'The app couldn’t verify this purchase. Check your Apple purchase history before buying again.',
      demo('Restore Purchases', 'btn primary') + demo('How to Check Purchase History', 'text-button')) +
    go('Keep Using Free', 'macs') + '<p class="helper">Any previously verified Pro access remains unchanged.</p>', 'macs'); });

add('display_info', 'Display & normal use', 'All Displays fallback', 'A display fallback is informational.',
  'If the server does not provide individual display positions, keep the session useful and explain why All Displays is shown.',
  ['A compact banner rather than a failure alert.', 'Desktop and keyboard controls remain usable.', 'No guessed layout or unnecessary reconnect.'],
  'Only use this when display metadata is absent. It must not mask a real connection failure.',
  function() { return desktop('<div class="notice"><strong>Showing all displays</strong>Individual display positions aren’t available from this Mac.</div>', false); });

add('desktop_connected', 'Display & normal use', 'Healthy Desktop', 'No permanent success-status clutter.',
  'Connection state appears when useful. A healthy session prioritizes the remote content.',
  ['One Done exit.', 'Menu controls are grouped.', 'Keyboard remains available.'],
  'This is a synthetic static desktop illustration, not a live session.',
  function() { return desktop('', false); });

add('terminal_connected', 'Display & normal use', 'Healthy Terminal', 'Keep recovery out of the healthy state.',
  'A connected shell focuses on terminal content rather than setup guidance.',
  ['Single exit and structured menu.', 'Setup appears before login or in Mac Settings.', 'No duplicated connected success labels.'],
  'All shown terminal text is synthetic. No shell, output capture or remote command runs in this page.',
  function() { return nav('Studio Mac<small>Terminal</small>', 'macs', demo('•••', 'pill circle')) +
    '<section class="content white"><div class="mono" style="font-size:14px;color:var(--text)">alex@studio-mac ~ % <span aria-hidden="true">▌</span></div></section>'; });

add('macs', 'Display & normal use', 'My Macs', 'Return to a simple host list.',
  'Use this synthetic home screen to explore entry points into Desktop, Terminal and Mac Settings.',
  ['A single Mac card.', 'Setup and connection actions remain distinct.', 'No unneeded permanent status.'],
  'All records in this prototype are invented. It does not read or modify your saved Macs.',
  function() { return page('My Macs', hero('mac', 'Your Macs, within reach', 'Desktop and Terminal, using macOS built-in sharing.') +
    '<div class="card"><div class="account-summary"><div class="account-avatar">▣</div><div><strong>Studio Mac</strong><small>Local network · Private VPN</small></div></div>' +
    row('Desktop', 'desktop_connected') + row('Terminal', 'key_login') + row('Mac Settings', 'mac_settings') + '</div>' +
    demo('Add Mac', 'btn') + demo('App Settings', 'text-button'), 'macs'); });

const params = new URLSearchParams(window.location.search);
if (params.get('embed') === '1') document.body.classList.add('embed');
if (params.get('theme') === 'dark') document.body.dataset.theme = 'dark';
const select = document.getElementById('scenario');
const list = document.getElementById('scenario-list');
const groups = [];
sceneList.forEach(function(scene) { if (!groups.includes(scene.group)) groups.push(scene.group); });
groups.forEach(function(group) {
  const optgroup = document.createElement('optgroup');
  optgroup.label = group;
  const heading = document.createElement('p');
  heading.className = 'scenario-group';
  heading.textContent = group;
  list.append(heading);
  sceneList.filter(function(s) { return s.group === group; }).forEach(function(scene) {
    const option = document.createElement('option');
    option.value = scene.id;
    option.textContent = scene.label;
    optgroup.append(option);
    const button = document.createElement('button');
    button.className = 'scenario-button';
    button.dataset.go = scene.id;
    button.textContent = scene.label;
    list.append(button);
  });
  select.append(optgroup);
});
function choose(id, updateURL) {
  const scene = sceneList.find(function(s) { return s.id === id; }) || sceneList[0];
  document.getElementById('screen').innerHTML = scene.render();
  document.getElementById('note-title').textContent = scene.title;
  document.getElementById('note-body').textContent = scene.body;
  const points = document.getElementById('note-points');
  points.replaceChildren();
  scene.points.forEach(function(point) {
    const li = document.createElement('li');
    li.textContent = point;
    points.append(li);
  });
  document.getElementById('note-constraint').textContent = scene.constraint;
  select.value = scene.id;
  list.querySelectorAll('[data-go]').forEach(function(button) {
    button.setAttribute('aria-current', String(button.dataset.go === scene.id));
  });
  if (updateURL) {
    const next = new URL(window.location.href);
    next.searchParams.set('scene', scene.id);
    history.replaceState(null, '', next);
  }
}
let toastTimer;
document.addEventListener('click', function(event) {
  const route = event.target.closest('[data-go]');
  if (route) choose(route.dataset.go, true);
  const action = event.target.closest('[data-demo]');
  if (action) {
    const toast = document.getElementById('demo-toast');
    toast.textContent = 'Design preview only. No action was performed.';
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function() { toast.hidden = true; }, 3000);
  }
});
select.addEventListener('change', function() { choose(select.value, true); });
document.getElementById('theme').addEventListener('click', function() {
  const dark = document.body.dataset.theme !== 'dark';
  document.body.dataset.theme = dark ? 'dark' : 'light';
  this.textContent = dark ? 'Light mode' : 'Dark mode';
});
document.getElementById('type').addEventListener('click', function() {
  const large = document.body.classList.toggle('large');
  this.textContent = large ? 'Standard text' : 'Large text';
  this.setAttribute('aria-pressed', String(large));
});
choose(params.get('scene'), false);
