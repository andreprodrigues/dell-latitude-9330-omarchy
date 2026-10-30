#!/bin/bash
# Fingerprint stack for the Dell Broadcom ControlVault 3 reader (0a5c:5843):
# patched libfprint-tod, Dell's TOD driver, the host-event shim, fprintd
# overrides, enrollment, then PAM. Safe to re-run; each step is idempotent.
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
src=${SRC_DIR:-$HOME/.local/src}
shim_repo=https://github.com/GrecAndrei/controlvault-fingerprint-passkey-toolkit
shim_rev=ea81ae2839c2be006dd7c00a29e8dd99a3f2d75b
shim_dir=$src/controlvault-fingerprint-passkey-toolkit

if ! lsusb -d 0a5c:5843 >/dev/null; then
  echo "No ControlVault 3 reader (0a5c:5843). Check BIOS: fingerprint reader enabled." >&2
  exit 1
fi

echo "== 1/5 libfprint-tod-cv3 (thermal model off for TOD v1 drivers)"
mkdir -p "$src/libfprint-tod-cv3"
cp "$here"/libfprint-tod-cv3/{PKGBUILD,tod-disable-thermal-model.patch} "$src/libfprint-tod-cv3/"
(cd "$src/libfprint-tod-cv3" && makepkg -si --needed)
sudo pacman -S --needed fprintd usbutils

echo "== 2/5 Dell's Broadcom TOD driver (first fprintd start may flash CV firmware)"
yay -S --needed libfprint-2-tod1-broadcom

echo "== 3/5 Host-event shim @ ${shim_rev:0:7}"
[[ -d $shim_dir ]] || git clone "$shim_repo" "$shim_dir"
git -C "$shim_dir" fetch -q origin
git -C "$shim_dir" checkout -q "$shim_rev"
make -C "$shim_dir/broadcom-host-event-shim" clean check
sudo install -o root -g root -m 0755 \
  "$shim_dir/broadcom-host-event-shim/libbcm-cv-host-event-shim.so" /usr/local/lib/

echo "== 4/5 fprintd overrides"
sudo install -d -m 0755 /etc/systemd/system/fprintd.service.d
sudo install -o root -g root -m 0644 "$here"/fprintd.service.d/*.conf /etc/systemd/system/fprintd.service.d/
sudo systemctl daemon-reload
sudo systemctl restart fprintd

echo "== 5/5 Enroll and verify"
if ! fprintd-list "$USER" | grep -q right-index-finger; then
  sudo fprintd-enroll -f right-index-finger "$USER"
fi
fprintd-verify
"$here/setup-pam.sh"
