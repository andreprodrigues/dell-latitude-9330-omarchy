# Dell Latitude 9330 on Omarchy: fingerprint, deep sleep, hibernate

Fixes that got a Dell Latitude 9330 fully working on [Omarchy](https://omarchy.org)
(Arch Linux): the Broadcom fingerprint reader, s2idle deep sleep and
suspend-then-hibernate. A bar widget checks all of them.

Each section starts with the symptom, so you can jump to what you're seeing.
The fingerprint part should also apply to other Dells with the same
ControlVault 3 reader (`0a5c:5843`). The upstream shim was first written for
a Latitude 7400.

Tested on BIOS 1.34.0, kernel 7.2.8, Omarchy 4.0.6, fprintd 1.94.5,
libfprint-tod 1.95.2, Broadcom TOD 5.15.021.0 (ControlVault firmware 5.15.21.0).

**Results:** fingerprint works for sudo, polkit and the lock screen. In a
10h51m lid-closed night the laptop spent 99% of the time in deep sleep,
drew 0.33 W and used 0.75% battery per hour. After 12 hours on battery it
hibernates and restores the session.

| Folder | What it is |
|---|---|
| [`fingerprint/`](fingerprint) | Patched libfprint-tod PKGBUILD, fprintd overrides, install and PAM scripts |
| [`widget/dell9330.health/`](widget/dell9330.health) | omarchy-shell bar widget, plus install scripts for the sleep and hibernate settings |

---

## Fingerprint (Broadcom ControlVault 3, `0a5c:5843`)

> [!WARNING]
> Do **not** run `omarchy-setup-security-fingerprint` on this laptop. It
> installs `libfprint-git`, which replaces the patched library below and
> breaks the reader. `fingerprint/setup-pam.sh` does that script's PAM part on
> its own.

Install everything (it asks for sudo and two finger touches at the end):

```sh
fingerprint/install.sh
```

It needs `yay`, which Omarchy ships. Here is what it does and why.

### Symptom: enroll or verify hangs after the first touch

Dell's Linux driver (`libfprint-2-tod1-broadcom`) ignores one message from
the chip. After a touch, the reader sends a "what time is it?" interrupt
(endpoint `0x85`, type 5). Dell's Windows driver answers it, but the Linux
driver tries a bulk read instead, times out, and the enroll or verify never
finishes. Launchpad bug
[2119302](https://bugs.launchpad.net/bugs/2119302).

**Fix:** [GrecAndrei's host-event shim](https://github.com/GrecAndrei/controlvault-fingerprint-passkey-toolkit/tree/ea81ae2839c2be006dd7c00a29e8dd99a3f2d75b/broadcom-host-event-shim)
(GPL-3.0). It's a small libusb interposer that answers only that interrupt.
It doesn't read or store fingerprint data. `install.sh` builds it at commit
`ea81ae2`, runs its tests and installs it to
`/usr/local/lib/libbcm-cv-host-event-shim.so`.
[`fprintd.service.d/broadcom-host-event-shim.conf`](fingerprint/fprintd.service.d/broadcom-host-event-shim.conf)
loads it into fprintd with `LD_PRELOAD`.

### Symptom: "Device disabled to prevent overheating" after about 3 minutes

libfprint has a thermal model that switches a reader off after a few minutes
of use. Dell's driver is an old-style (TOD v1) driver that was built before
that setting existed, so it silently gets the 3-minute default. A lock screen
or a slow enroll left waiting runs into it.

**Fix:** [`tod-disable-thermal-model.patch`](fingerprint/libfprint-tod-cv3/tod-disable-thermal-model.patch)
turns the model off for TOD v1 drivers, which are all match-on-chip readers.
The [PKGBUILD](fingerprint/libfprint-tod-cv3/PKGBUILD) is AUR
`libfprint-tod` with that patch, renamed to `libfprint-tod-cv3` so that
`yay -Syu` doesn't replace it. After an AUR `libfprint-tod` update, rebuild
it with `cd ~/.local/src/libfprint-tod-cv3 && makepkg -si`.

### Symptom: fprintd fails to start the first time

The first start of the Broadcom driver can flash the reader's firmware
(here 5.15.10.0 to 5.15.21.0), which takes longer than systemd's default
start timeout.
[`broadcom-fw-timeout.conf`](fingerprint/fprintd.service.d/broadcom-fw-timeout.conf)
raises it to 5 minutes.

> [!NOTE]
> With the lid shut (docked), the PAM gate skips the reader and you get the
> password prompt straight away. Otherwise sudo waits for a touch first, and
> asks for the password if you don't touch the reader.

**Undo:** remove `/etc/systemd/system/fprintd.service.d/broadcom-*.conf` and
`/usr/local/lib/libbcm-cv-host-event-shim.so`, remove the two lines that
mention `pam_fprintd` and `omarchy-hw-laptop-closed` from `/etc/pam.d/sudo`
and `/etc/pam.d/polkit-1`, then `sudo pacman -S libfprint`.

---

## Deep sleep (s2idle / S0ix)

### Symptom: the battery drains overnight with the lid closed

This laptop only has s2idle (no S3). With the BIOS storage mode set to
**RAID On** (Intel VMD), the firmware forbids Linux from putting the NVMe link
into a low-power state (ASPM). The package never gets past PC3, so it spends
0% of sleep in S0ix.

To check, compare this counter before and after a sleep. If it doesn't
increase, the laptop never reached deep sleep:

```sh
cat /sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us
```

**Fix:** in the BIOS, go to **Storage** and switch from **RAID On** to
**AHCI/NVMe**. A 138 s lid-closed test then gave 135.8 s in S0ix (98%).

> [!CAUTION]
> Linux booted fine after the switch here. If you also dual-boot Windows on
> this drive, Windows may not boot after the switch unless you prepare it
> first (search for "switch RAID to AHCI Windows safe mode").

---

## Suspend-then-hibernate

Closing the lid suspends (s2idle) first. After 12 hours on battery, or when
the battery gets low, the laptop wakes up and hibernates. On the charger it
stays suspended.

You need hibernation set up first: a swapfile and `resume=` in the kernel
command line. `omarchy-hibernation-setup` does that. On an encrypted
install, resuming asks for the disk (LUKS) passphrase.

```sh
widget/dell9330.health/install-suspend-then-hibernate            # --remove to undo
```

It writes `/etc/systemd/logind.conf.d/dell-health-lid.conf` and
`/etc/systemd/sleep.conf.d/dell-health-hibernate.conf`, then reloads logind
without ending your session.

### Symptom: hibernate starts, then rolls back to the desktop

The kernel log shows `mtk_t7xx 0000:72:00.0 ... -110` and then
`Wakeup event detected during hibernation`. The driver for the MediaTek
T700 5G modem times out at the final power-off step, so the kernel cancels
the hibernate.

**Fix**, if you don't use mobile data: stop that driver from loading.

```sh
widget/dell9330.health/install-no-wwan                           # --remove to undo
```

It writes `/etc/modprobe.d/dell-health-no-wwan.conf` (`blacklist mtk_t7xx`).
Reboot, then test with `systemctl hibernate`. The screen can freeze on the
lock screen for a few seconds while the image is written. That's normal.

> [!TIP]
> `journalctl -k` only shows the current boot. To read a failed hibernate
> attempt from before a reboot, use `journalctl -k -b -1`.

---

## Health widget

An omarchy-shell bar widget with a detail panel, so you can see at a glance
whether any of the above has broken, for example after an update replaces a
package:

- **Fingerprint:** reader detected, patched library, Broadcom driver, shim
  loaded into fprintd, fingers enrolled, PAM in use.
- **Sleep:** BIOS storage mode, deep sleep % and battery drain for the last
  sleep (%/hour, W, estimated standby days), 7-day average, whether
  hibernation is ready.
- **Battery and system:** charge, health, charge limit, BIOS and
  ControlVault firmware versions.

Every failed check shows a hint with the command that fixes it.

```sh
cp -r widget/dell9330.health ~/.config/omarchy/plugins/
~/.config/omarchy/plugins/dell9330.health/install-sleep-hook   # optional: battery drain tracking
```

Then add **Dell health** to the bar from omarchy-shell's bar settings. To get
the same report in a terminal, run `dell-health --text` from the plugin
folder. The widget itself needs no root. The optional sleep hook logs charge
and S0ix counters at each suspend and resume to
`/var/lib/dell-health/sleep.log`.

---

## Credits and licenses

- Host-event shim: Grec Andrei Alexander,
  [controlvault-fingerprint-passkey-toolkit](https://github.com/GrecAndrei/controlvault-fingerprint-passkey-toolkit)
  (GPL-3.0-or-later). Linked, not included here.
- libfprint / libfprint-tod: freedesktop.org and Marco Trevisan
  (LGPL-2.1-or-later). The patch in `fingerprint/libfprint-tod-cv3` is under
  the same license. The PKGBUILD is based on AUR `libfprint-tod`.
- `libfprint-2-tod1-broadcom` is Dell's proprietary driver, installed from
  the AUR and not included here.
- Everything else in this repo is MIT, see [LICENSE](LICENSE).

This works on one laptop. It isn't official Dell or Omarchy support, and it
changes PAM and system files, so read the scripts before running them.
