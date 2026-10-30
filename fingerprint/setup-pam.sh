#!/bin/bash
# Fingerprint for sudo, polkit and the Omarchy lock screen. Same PAM lines as
# omarchy-setup-security-fingerprint, without that script's package step (it
# installs libfprint-git, which replaces libfprint-tod-cv3 and breaks the reader).
# The clamshell gate skips the reader when the lid is shut, so PAM falls
# straight through to the password prompt.
set -euo pipefail

gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"

add_fprintd() { # pam file
  grep -q pam_fprintd.so "$1" || sudo sed -i '1i auth      sufficient pam_fprintd.so' "$1"
  grep -q omarchy-hw-laptop-closed "$1" || sudo sed -i "/pam_fprintd\.so/i $gate" "$1"
}

add_fprintd /etc/pam.d/sudo

if [[ -f /etc/pam.d/polkit-1 ]]; then
  add_fprintd /etc/pam.d/polkit-1
else
  sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
$gate
auth      sufficient pam_fprintd.so
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
fi

sudo tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so
account    include                     system-local-login
EOF

echo "Fingerprint enabled for sudo, polkit and the lock screen"
