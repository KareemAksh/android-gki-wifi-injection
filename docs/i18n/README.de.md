<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.fr.md">Français</a> ·
  <b>Deutsch</b> ·
  <a href="README.zh.md">中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

# WLAN-Injection auf einem unveränderten Android-GKI-Kernel

> **Monitor-Modus und 802.11-Paketinjektion auf einem Standard-Android-Smartphone**, indem `cfg80211` + `mac80211` + `rtl8xxxu` als ladbare Module für einen GKI-Kernel kompiliert werden — ohne Custom-ROM, ohne Kernel-Flash.

Zielgerät: **Redmi Note 13 4G** (`sapphire`, Qualcomm `khaje`), Kernel `5.15.178-android13-8`, gerootet mit Magisk.

> ⚠️ **Nur für autorisierte Tests.** Forschungs-/Lernprojekt, ausschließlich an eigenen Netzwerken des Autors genutzt. Deauthentifizierung stört den Betrieb und ist gegen fremde Netzwerke illegal.

## Kurzfassung

- Der GKI-Kernel hat ein **eingefrorenes KMI**, **kein `mac80211`** und nur ein herstellereigenes Qualcomm-`cfg80211`. Daher kann kein USB-Adapter standardmäßig Monitor-Modus/Injektion.
- Dieses Projekt baut **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`** gegen die **exakte GKI-Quelle und `vmlinux.symvers`** (identische vermagic, voller **LTO/CFI/SCS**-Build mit Clang 14) und **tauscht** den Hersteller-WLAN-Stack zur Laufzeit aus, damit der OTG-Adapter läuft.
- **RTL8188F**-Unterstützung (in Linux 6.5 hinzugefügt) wurde auf den 5.15-Treiber **zurückportiert**, und die Firmware ist **ins Modul eingebettet**, um SELinux zu umgehen.
- Eine **Flutter-App** steuert alles als root: Stack-Tausch → Erkennung → Scan → Injektionstest (`aireplay-ng -9`) → Deauth.
- **Erkenntnis:** Das interne Qualcomm-WLAN lässt sich in den Monitor-Modus zwingen (nur Mitlesen), aber die Firmware **unterstützt keine Injektion** — Deauth über den internen Chip ist unmöglich. Der OTG-Adapter ist der einzige injektionsfähige Weg.

## Warum das schwierig ist (das GKI-Problem)

| Hürde | Detail |
|---|---|
| Kein `mac80211` | Der GKI-Kernel baut es nicht; der Qualcomm-Treiber ist FullMAC. |
| Hersteller-`cfg80211` | Qualcomm-Modul (vermagic `5.15.94`), dessen CRCs nicht zum Standard-ACK passen. |
| `MODVERSIONS` + vermagic | Jedes Modul muss exakt `5.15.178-android13-8-...` entsprechen. |
| Volles LTO + CFI + SCS | Ohne passendes Clang-CFI stürzt der Kernel beim ersten indirekten Aufruf ab. |
| `nl80211` ist Singleton | Kein zweites `cfg80211` ladbar — der Stack muss **getauscht** werden. |
| Firmware-Loader / SELinux | Der Kernel kann Firmware nicht aus `/data/local/tmp` lesen. |

## Bauen

```bash
# 1) Kernel-Module für deinen GKI-Build bauen
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) Statische Userspace-Tools bauen
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) Einbinden und APK bauen
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## Nutzung (App)

1. **Prepare** — root in Magisk erlauben; der Stack wird getauscht.
2. OTG-Adapter anschließen → **Detect** (`wlan0`).
3. **Test inject** — führt `aireplay-ng -9` aus; erwartet: *„Injection is working!"*.
4. **Scan** → **Deauth** auf ein Netzwerk, **das dir gehört**.
5. **Restore** — ein Neustart stellt das interne WLAN wieder her.

## Lizenz

Unter **GPL-2.0** — enthält modifizierten Code aus `rtl8xxxu`/`mac80211`/`cfg80211` (Linux-Kernel).
