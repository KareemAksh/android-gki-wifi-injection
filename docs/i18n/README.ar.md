<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <b>العربية</b> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.zh.md">中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

<div dir="rtl">

# حقن إطارات WiFi على نواة أندرويد GKI الأصلية

> **وضع المراقبة (Monitor) وحقن إطارات 802.11 على هاتف أندرويد بنواة أصلية** عبر بناء وحدات `cfg80211` و`mac80211` و`rtl8xxxu` كوحدات قابلة للتحميل (loadable modules) — بدون روم مخصص وبدون تفليش النواة.

الجهاز المستهدف: **Redmi Note 13 4G** (الاسم الرمزي `sapphire`، معالج Qualcomm `khaje`)، النواة `5.15.178-android13-8`، مع صلاحيات الروت عبر Magisk.

> ⚠️ **للاختبار المُصرَّح به فقط.** هذا المشروع بحثي تعليمي استُخدم على شبكات المؤلف الخاصة فقط. هجوم فك الارتباط (Deauth) معطِّل للخدمة، واستخدامه ضد شبكات لا تملكها غير قانوني في معظم الدول.

## نظرة سريعة

- نواة أندرويد GKI تأتي بواجهة وحدات مجمَّدة (frozen KMI)، **بدون `mac80211`**، ومع `cfg80211` خاص بـ Qualcomm. لذلك لا يستطيع أي محول USB العمل في وضع المراقبة أو الحقن افتراضيًا.
- يبني المشروع **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`** مقابل **مصدر GKI و`vmlinux.symvers` بالضبط**، مع مطابقة الـ vermagic وبناء كامل بـ **LTO/CFI/SCS** باستخدام Clang 14، ثم **يستبدل** مكدّس الواي‑فاي للمصنّع وقت التشغيل ليعمل محول OTG.
- تم **نقل دعم RTL8188F** (المضاف في لينكس 6.5) إلى مشغّل 5.15، مع **تضمين الـ firmware داخل الوحدة** لتجاوز قيود SELinux.
- يتولّى **تطبيق Flutter** كل الخطوات بصلاحيات الروت: استبدال المكدّس ← كشف المحول ← فحص ← اختبار الحقن (`aireplay-ng -9`) ← deauth.
- **النتيجة:** يمكن إجبار واي‑فاي Qualcomm الداخلي على وضع المراقبة (للتنصّت فقط) لكن الـ firmware **لا يدعم الحقن** — لذا الـ deauth عبر الشريحة الداخلية مستحيل؛ محول OTG هو المسار الوحيد القادر على الحقن.

## لماذا هذا صعب (مشكلة GKI)

| العائق | التفاصيل |
|---|---|
| لا يوجد `mac80211` | نواة GKI لا تبنيه أصلًا؛ مشغّل Qualcomm من نوع FullMAC. |
| `cfg80211` خاص بالمصنّع | الوحدة المحمّلة من Qualcomm (vermagic `5.15.94`) وبصمات الرموز (CRC) لا تطابق المصدر القياسي. |
| `MODVERSIONS` + vermagic مطابق | أي وحدة يجب أن تطابق `5.15.178-android13-8-...` وبصمات GKI تمامًا. |
| LTO + CFI + SCS كامل | بدون CFI مطابق من Clang، تنهار النواة عند أول استدعاء غير مباشر. |
| `nl80211` فريد | لا يمكن تحميل `cfg80211` ثانٍ — لذا يجب **استبدال** المكدّس لا إضافته. |
| محمّل firmware وSELinux | النواة لا تقرأ الـ firmware من `/data/local/tmp`. |

## البناء

```bash
# 1) بناء وحدات النواة لإصدار GKI الخاص بجهازك
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) بناء أدوات المستخدم الثابتة (static)
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) تجهيز التطبيق وبناء الـ APK
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## الاستخدام (التطبيق)

1. **Prepare** — امنح الروت من نافذة Magisk؛ يتم استبدال المكدّس.
2. صِل محول OTG ← **Detect** (يظهر `wlan0`).
3. **Test inject** — يشغّل `aireplay-ng -9`؛ المتوقع *"Injection is working!"*.
4. **Scan** ← اضغط **Deauth** على شبكة **تملكها أنت**.
5. **Restore** — إعادة التشغيل تعيد الواي‑فاي الداخلي لطبيعته.

## الترخيص

مرخّص تحت **GPL-2.0** لأنه يحتوي على كود معدَّل من `rtl8xxxu`/`mac80211`/`cfg80211` (نواة لينكس).

</div>
