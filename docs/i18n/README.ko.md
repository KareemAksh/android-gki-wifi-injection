<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.zh.md">中文</a> ·
  <b>한국어</b> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

# 순정 Android GKI 커널에서의 WiFi 인젝션

> **순정 Android 폰에서 모니터 모드 및 802.11 패킷 인젝션** 구현 — `cfg80211` + `mac80211` + `rtl8xxxu`를 GKI 커널용 로더블 모듈로 빌드. 커스텀 ROM도, 커널 플래시도 필요 없음.

대상 기기: **Redmi Note 13 4G**(`sapphire`, Qualcomm `khaje`), 커널 `5.15.178-android13-8`, Magisk 루팅.

> ⚠️ **허가된 테스트 전용.** 연구/학습 프로젝트로, 작성자 본인 네트워크에서만 사용했습니다. 디인증(deauth)은 서비스를 중단시키며 본인 소유가 아닌 네트워크에 대한 사용은 불법입니다.

## 요약

- GKI 커널은 **고정된 KMI**를 가지며 **`mac80211`이 없고** Qualcomm 전용 `cfg80211`만 있습니다. 따라서 기본 상태에서는 어떤 USB 어댑터도 모니터 모드/인젝션이 불가능합니다.
- 본 프로젝트는 **정확한 GKI 소스와 `vmlinux.symvers`** 에 맞춰 **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`** 를 빌드하고(vermagic 완전 일치, Clang 14의 전체 **LTO/CFI/SCS** 빌드), 런타임에 제조사 WiFi 스택을 **교체**하여 OTG 어댑터를 동작시킵니다.
- **RTL8188F** 지원(Linux 6.5에서 추가)을 5.15 드라이버로 **백포트**하고, SELinux 제약을 우회하기 위해 펌웨어를 **모듈에 내장**했습니다.
- **Flutter 앱**이 root로 전 과정을 제어합니다: 스택 교체 → 어댑터 감지 → 스캔 → 인젝션 테스트(`aireplay-ng -9`) → deauth.
- **결론:** 내장 Qualcomm WiFi는 모니터 모드로 강제 전환은 되지만(스니핑만 가능) 펌웨어가 **인젝션을 지원하지 않습니다** — 내장 칩으로는 deauth가 불가능합니다. OTG 어댑터만이 인젝션 가능한 경로입니다.

## 왜 어려운가 (GKI 문제)

| 장애물 | 설명 |
|---|---|
| `mac80211` 없음 | GKI 커널이 빌드하지 않음; Qualcomm 드라이버는 FullMAC. |
| 제조사 `cfg80211` | Qualcomm 모듈(vermagic `5.15.94`)의 심볼 CRC가 표준 ACK와 불일치. |
| `MODVERSIONS` + vermagic | 모든 모듈이 `5.15.178-android13-8-...` 와 정확히 일치해야 함. |
| 전체 LTO + CFI + SCS | 일치하는 Clang CFI 없이는 첫 간접 호출에서 커널 패닉. |
| `nl80211` 싱글톤 | 두 번째 `cfg80211`을 로드할 수 없음 — 스택을 **교체**해야 함. |
| 펌웨어 로더 / SELinux | 커널이 `/data/local/tmp`에서 펌웨어를 읽지 못함. |

## 빌드

```bash
# 1) 본인 GKI 빌드에 맞춰 커널 모듈 빌드
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) 정적 유저스페이스 도구 빌드
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) 앱에 포함하고 APK 빌드
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## 사용법 (앱)

1. **Prepare** — Magisk 팝업에서 root 허용; 스택이 교체됩니다.
2. OTG 어댑터 연결 → **Detect** (`wlan0` 표시).
3. **Test inject** — `aireplay-ng -9` 실행; *"Injection is working!"* 기대.
4. **Scan** → **본인 소유** 네트워크에 **Deauth**.
5. **Restore** — 재부팅하면 내장 WiFi가 복원됩니다.

## 라이선스

**GPL-2.0** — `rtl8xxxu`/`mac80211`/`cfg80211`(Linux 커널)의 수정 코드를 포함합니다.
