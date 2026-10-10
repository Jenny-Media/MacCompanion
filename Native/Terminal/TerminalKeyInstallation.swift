#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

enum TerminalKeyInstallation {
    /// Fixed command; only the validated public-key algorithm/blob and UUID enter it.
    static func command(for entry: TerminalNamedKey) throws -> String {
        try entry.key.validate()
        let fields = entry.key.publicKey.split(separator: " ")
        guard fields.count == 2, fields[0] == "ssh-ed25519",
              Data(base64Encoded: String(fields[1])) != nil else { throw TerminalSecretStore.Failure.storage }
        let blob = String(fields[1])
        let script = """
        set -eu
        umask 077
        ssh_dir="$HOME/.ssh"
        auth_file="$ssh_dir/authorized_keys"
        [ ! -L "$ssh_dir" ] || exit 21
        [ ! -e "$ssh_dir" ] || [ -d "$ssh_dir" ] || exit 22
        mkdir -p "$ssh_dir"
        [ -O "$ssh_dir" ] || exit 23
        [ ! -L "$auth_file" ] || exit 24
        [ ! -e "$auth_file" ] || { [ -f "$auth_file" ] && [ -O "$auth_file" ] && [ "$(/usr/bin/stat -f %l "$auth_file")" = 1 ]; } || exit 25
        lock_dir="$ssh_dir/.mac-companion-key-install.lock"
        mkdir "$lock_dir" || exit 26
        tmp_file=""
        trap '[ -z "$tmp_file" ] || rm -f "$tmp_file"; rmdir "$lock_dir"' EXIT
        chmod 700 "$ssh_dir"
        original="missing"
        if [ -e "$auth_file" ]; then
            original="$(cksum < "$auth_file")"
            chmod 600 "$auth_file"
            if awk -v k='\(blob)' '
                function field( start,c,quoted,escaped) {
                    while (pos<=length(line) && substr(line,pos,1) ~ /[[:space:]]/) pos++
                    start=pos; quoted=0; escaped=0
                    while (pos<=length(line)) {
                        c=substr(line,pos,1)
                        if (escaped) escaped=0
                        else if (c==sprintf("%c",92)) escaped=1
                        else if (c==sprintf("%c",34)) quoted=!quoted
                        else if (!quoted && c ~ /[[:space:]]/) break
                        pos++
                    }
                    if (quoted || escaped) return ""
                    return substr(line,start,pos-start)
                }
                $0 !~ /^[[:space:]]*#/ {
                    line=$0; pos=1; algorithm=field()
                    if (algorithm!="ssh-ed25519") algorithm=field()
                    if (algorithm=="ssh-ed25519" && field()==k) {found=1; exit}
                }
                END {exit(found?0:1)}' "$auth_file"; then
                printf 'MC_KEY_PRESENT\\n'
                exit 0
            fi
        fi
        tmp_file="$(mktemp "$ssh_dir/.mac-companion-authorized.XXXXXX")"
        if [ -e "$auth_file" ]; then cat "$auth_file" > "$tmp_file"; printf '\\n' >> "$tmp_file"; fi
        printf '%s\\n' 'ssh-ed25519 \(blob) mac-companion-\(entry.id.uuidString.lowercased())' >> "$tmp_file"
        chmod 600 "$tmp_file"
        [ ! -L "$ssh_dir" ] && [ -O "$ssh_dir" ] && [ ! -L "$auth_file" ] || exit 27
        if [ "$original" = missing ]; then [ ! -e "$auth_file" ] || exit 28
        else [ -f "$auth_file" ] && [ -O "$auth_file" ] && [ "$(/usr/bin/stat -f %l "$auth_file")" = 1 ] && [ "$(cksum < "$auth_file")" = "$original" ] || exit 29; fi
        mv -f "$tmp_file" "$auth_file"
        tmp_file=""
        printf 'MC_KEY_INSTALLED\\n'
        """
        return "/bin/sh -c '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
