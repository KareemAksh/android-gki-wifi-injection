<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.ar.md">العربية</a> ·
  <b>Français</b> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.zh.md">中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

# Injection WiFi sur un noyau Android GKI d'origine

> **Mode moniteur et injection de trames 802.11 sur un téléphone Android non modifié**, en compilant `cfg80211` + `mac80211` + `rtl8xxxu` comme modules chargeables pour un noyau GKI — sans ROM personnalisée ni flash du noyau.

Appareil cible : **Redmi Note 13 4G** (`sapphire`, Qualcomm `khaje`), noyau `5.15.178-android13-8`, rooté avec Magisk.

> ⚠️ **Tests autorisés uniquement.** Projet de recherche/apprentissage, utilisé uniquement sur les réseaux de l'auteur. La désauthentification (deauth) perturbe le service et est illégale contre des réseaux que vous ne possédez pas.

## En bref

- Le noyau GKI a une **KMI figée**, **sans `mac80211`**, avec un `cfg80211` propriétaire Qualcomm. Aucun adaptateur USB ne peut donc faire de mode moniteur/injection par défaut.
- Ce projet compile **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`** contre la **source GKI et le `vmlinux.symvers` exacts** (vermagic identique, build complet **LTO/CFI/SCS** avec Clang 14), puis **remplace** la pile WiFi du constructeur à l'exécution pour activer l'adaptateur OTG.
- Le support **RTL8188F** (ajouté dans Linux 6.5) est **rétroporté** vers le pilote 5.15, et le firmware est **intégré au module** pour contourner SELinux.
- Une **application Flutter** orchestre le tout en root : remplacement de pile → détection → scan → test d'injection (`aireplay-ng -9`) → deauth.
- **Constat :** le WiFi Qualcomm interne peut passer en mode moniteur (écoute seulement), mais son firmware **ne supporte pas l'injection** — le deauth via la puce interne est impossible. L'adaptateur OTG est la seule voie capable d'injecter.

## Pourquoi c'est difficile (le problème GKI)

| Obstacle | Détail |
|---|---|
| Pas de `mac80211` | Le noyau GKI ne le compile pas ; le pilote Qualcomm est FullMAC. |
| `cfg80211` du constructeur | Module Qualcomm (vermagic `5.15.94`) dont les CRC ne correspondent pas à l'ACK standard. |
| `MODVERSIONS` + vermagic | Tout module doit correspondre exactement à `5.15.178-android13-8-...`. |
| LTO + CFI + SCS complet | Sans CFI Clang correspondant, le noyau plante au premier appel indirect. |
| `nl80211` unique | Impossible de charger un second `cfg80211` — il faut **remplacer** la pile. |
| Chargeur de firmware / SELinux | Le noyau ne peut pas lire le firmware depuis `/data/local/tmp`. |

## Compilation

```bash
# 1) Compiler les modules noyau pour votre build GKI
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) Compiler les outils statiques
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) Intégrer et compiler l'APK
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## Utilisation (application)

1. **Prepare** — accordez le root dans Magisk ; la pile est remplacée.
2. Branchez l'adaptateur OTG → **Detect** (`wlan0`).
3. **Test inject** — exécute `aireplay-ng -9` ; attendu : *« Injection is working! »*.
4. **Scan** → **Deauth** sur un réseau **que vous possédez**.
5. **Restore** — un redémarrage restaure le WiFi interne.

## Licence

Sous **GPL-2.0** — contient du code modifié de `rtl8xxxu`/`mac80211`/`cfg80211` (noyau Linux).
