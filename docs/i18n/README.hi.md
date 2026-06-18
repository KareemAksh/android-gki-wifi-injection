<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.zh.md">中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <b>हिन्दी</b>
</p>

# स्टॉक Android GKI कर्नेल पर WiFi इंजेक्शन

> **बिना मॉडिफाई किए Android फ़ोन पर मॉनिटर मोड और 802.11 पैकेट इंजेक्शन** — `cfg80211` + `mac80211` + `rtl8xxxu` को GKI कर्नेल के लिए loadable modules के रूप में कंपाइल करके। न कस्टम ROM, न कर्नेल फ़्लैश।

लक्ष्य डिवाइस: **Redmi Note 13 4G** (`sapphire`, Qualcomm `khaje`), कर्नेल `5.15.178-android13-8`, Magisk से रूटेड।

> ⚠️ **केवल अधिकृत परीक्षण।** यह एक शोध/शिक्षण परियोजना है, केवल लेखक के अपने नेटवर्क पर उपयोग की गई। Deauth सेवा बाधित करता है और दूसरों के नेटवर्क पर इसका उपयोग अधिकांश देशों में अवैध है।

## संक्षेप में

- GKI कर्नेल में **फ़्रोज़न KMI** है, **`mac80211` नहीं** है, और केवल Qualcomm का अपना `cfg80211` है। इसलिए डिफ़ॉल्ट रूप से कोई भी USB अडैप्टर मॉनिटर मोड/इंजेक्शन नहीं कर सकता।
- यह प्रोजेक्ट **सटीक GKI सोर्स और `vmlinux.symvers`** के विरुद्ध **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`** बनाता है (vermagic पूर्णतः मेल खाता, Clang 14 के साथ पूर्ण **LTO/CFI/SCS** बिल्ड), फिर रनटाइम पर वेंडर WiFi स्टैक को **बदल** देता है ताकि OTG अडैप्टर काम करे।
- **RTL8188F** सपोर्ट (Linux 6.5 में जोड़ा गया) को 5.15 ड्राइवर में **बैकपोर्ट** किया गया, और SELinux की बाधाओं से बचने हेतु फ़र्मवेयर को **मॉड्यूल में एम्बेड** किया गया।
- एक **Flutter ऐप** सब कुछ root के रूप में संचालित करता है: स्टैक स्वैप → अडैप्टर पहचान → स्कैन → इंजेक्शन टेस्ट (`aireplay-ng -9`) → deauth।
- **निष्कर्ष:** आंतरिक Qualcomm WiFi को मॉनिटर मोड में लाया जा सकता है (केवल सूँघना/sniff), पर इसका फ़र्मवेयर **इंजेक्शन सपोर्ट नहीं करता** — इसलिए आंतरिक चिप से deauth असंभव है। OTG अडैप्टर ही एकमात्र इंजेक्शन-सक्षम रास्ता है।

## यह कठिन क्यों है (GKI समस्या)

| बाधा | विवरण |
|---|---|
| `mac80211` नहीं | GKI कर्नेल इसे बिल्ड ही नहीं करता; Qualcomm ड्राइवर FullMAC है। |
| वेंडर `cfg80211` | Qualcomm मॉड्यूल (vermagic `5.15.94`) जिसके CRC स्टैंडर्ड ACK से मेल नहीं खाते। |
| `MODVERSIONS` + vermagic | हर मॉड्यूल को `5.15.178-android13-8-...` से सटीक मेल खाना चाहिए। |
| पूर्ण LTO + CFI + SCS | मेल खाते Clang CFI के बिना पहले इनडायरेक्ट कॉल पर कर्नेल क्रैश। |
| `nl80211` सिंगलटन | दूसरा `cfg80211` लोड नहीं हो सकता — स्टैक को **बदलना** ही पड़ता है। |
| फ़र्मवेयर लोडर / SELinux | कर्नेल `/data/local/tmp` से फ़र्मवेयर नहीं पढ़ सकता। |

## बिल्ड

```bash
# 1) अपने GKI बिल्ड के लिए कर्नेल मॉड्यूल बनाएँ
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) स्टैटिक यूज़रस्पेस टूल बनाएँ
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) ऐप में जोड़ें और APK बनाएँ
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## उपयोग (ऐप)

1. **Prepare** — Magisk पॉपअप में root दें; स्टैक स्वैप हो जाता है।
2. OTG अडैप्टर लगाएँ → **Detect** (`wlan0` दिखेगा)।
3. **Test inject** — `aireplay-ng -9` चलाता है; अपेक्षित: *"Injection is working!"*।
4. **Scan** → **अपने स्वामित्व वाले** नेटवर्क पर **Deauth**।
5. **Restore** — रीबूट करने पर आंतरिक WiFi पुनः सामान्य हो जाता है।

## लाइसेंस

**GPL-2.0** के तहत — इसमें `rtl8xxxu`/`mac80211`/`cfg80211` (Linux कर्नेल) का संशोधित कोड शामिल है।
