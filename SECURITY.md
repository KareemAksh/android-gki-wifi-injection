# Security & Responsible Use

## Intended use

This project is published for **education, security research, and authorized testing only**. It implements 802.11 monitor mode and packet injection (including deauthentication), which are **disruptive** and **regulated** capabilities.

You may use it **only** on:
- networks and devices **you own**, or
- networks you have **explicit, written authorization** to test.

Unauthorized interception or disruption of wireless networks is illegal under laws such as the US **Computer Fraud and Abuse Act**, the UK **Computer Misuse Act**, the EU **Directive 2013/40/EU**, and equivalents worldwide. The authors and contributors accept **no liability** for misuse.

## Scope

This repository contains kernel modules, a driver backport, build scripts, and a mobile app. It is research tooling — **not** a hardened product. Running it requires root, swaps your device's WiFi stack, and is **reversible by reboot**.

## Reporting a vulnerability

If you find a security issue in this code (e.g. a memory-safety bug in the driver backport or the deauth tool), please open a **private** report via GitHub Security Advisories ("Report a vulnerability" on the Security tab) rather than a public issue. Include reproduction steps and affected files. Best-effort response within a reasonable timeframe; this is a volunteer research project.

## Out of scope

- Requests for help attacking networks you do not own.
- Vulnerabilities in upstream projects (`linux`, `aircrack-ng`, `iw`, `libnl`) — report those to their maintainers.
