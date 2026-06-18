# Contributing

Thanks for your interest! Contributions are welcome — bug fixes, new adapter/chipset support, ports to other GKI builds, documentation, and translations.

## Ground rules

- This is **defensive/educational security tooling**. Contributions that exist only to attack third-party networks will be declined. See [SECURITY.md](SECURITY.md).
- By contributing, you agree your work is licensed under the project's **GPL-2.0** license.

## How to contribute

1. Open an issue first for anything non-trivial (new chipset, new kernel target) so we can align.
2. Fork, create a feature branch, keep commits focused and descriptive.
3. Open a Pull Request that explains **what** and **why**, with test notes (device, `uname -r`, what you verified).

## Porting to another device / kernel

Most "it doesn't load" issues are a **vermagic / `vmlinux.symvers` mismatch**. To target a different GKI build:

1. Read the target's `uname -r` and `/proc/version` (the `-abNNNN` is the GKI build number).
2. Set `GKI_BUILD`, `KCOMMON_SHA`, and `SCMVERSION` in [`scripts/build_modules.sh`](scripts/build_modules.sh).
3. Provide `device_config` (`adb shell su -c 'zcat /proc/config.gz' > device_config`).
4. Rebuild; verify `modinfo -F vermagic *.ko` matches `uname -r` exactly.

See [`docs/TECHNICAL-NOTES.md`](docs/TECHNICAL-NOTES.md) for the deep details (CRC matching, CFI/LTO, the 8188F backport, SELinux firmware embedding).

## Adding chipset support

`rtl8xxxu` covers many Realtek USB chips. For a non-Realtek adapter you'd add its mainline driver to the build the same way (compile against the GKI headers, shim any mac80211 API drift, embed firmware if SELinux blocks the loader).

## Style

- Kernel/driver code: follow Linux kernel style.
- Shell: POSIX `sh` (the engine runs under Android's `/system/bin/sh`).
- Dart: `flutter analyze` must pass.
