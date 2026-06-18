<p align="center">
  <img src="../../assets/banner.svg" alt="Android GKI WiFi Injection" width="100%">
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <b>中文</b> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.hi.md">हिन्दी</a>
</p>

# 在原版 Android GKI 内核上实现 WiFi 注入

> **在未改动的 Android 手机上实现监听模式（monitor mode）与 802.11 数据包注入**：把 `cfg80211` + `mac80211` + `rtl8xxxu` 编译为 GKI 内核的可加载模块 —— 无需第三方 ROM，无需刷写内核。

目标设备：**Redmi Note 13 4G**（代号 `sapphire`，高通 `khaje`），内核 `5.15.178-android13-8`，已用 Magisk 取得 root。

> ⚠️ **仅限授权测试。** 这是研究/学习项目，仅在作者自有网络上使用。去认证攻击（deauth）会中断服务，针对非自有网络属于违法行为。

## 摘要

- GKI 内核采用**冻结的 KMI**，**不含 `mac80211`**，只有高通自带的 `cfg80211`。因此默认情况下任何 USB 网卡都无法进入监听模式或注入。
- 本项目针对**精确的 GKI 源码与 `vmlinux.symvers`**编译出 **`cfg80211.ko` + `mac80211.ko` + `rtl8xxxu.ko`**（vermagic 完全匹配，使用 Clang 14 的完整 **LTO/CFI/SCS** 构建），再在运行时**替换**厂商 WiFi 栈，使 OTG 网卡工作。
- 将 **RTL8188F** 支持（Linux 6.5 才加入）**回移植**到 5.15 驱动，并把固件**内嵌进模块**以绕过 SELinux 限制。
- 一个 **Flutter 应用**以 root 编排全流程：替换内核栈 → 识别网卡 → 扫描 → 注入测试（`aireplay-ng -9`）→ deauth。
- **结论：** 内置高通 WiFi 可被强制进入监听模式（仅能嗅探），但其固件**不支持注入** —— 因此无法用内置芯片做 deauth。OTG 网卡是唯一能注入的途径。

## 为何困难（GKI 难题）

| 障碍 | 说明 |
|---|---|
| 没有 `mac80211` | GKI 内核根本不编译它；高通驱动是 FullMAC。 |
| 厂商 `cfg80211` | 高通模块（vermagic `5.15.94`），其符号 CRC 与标准 ACK 不一致。 |
| `MODVERSIONS` + vermagic | 任何模块都必须精确匹配 `5.15.178-android13-8-...`。 |
| 完整 LTO + CFI + SCS | 若无匹配的 Clang CFI，内核会在首次间接调用时崩溃。 |
| `nl80211` 单例 | 无法加载第二个 `cfg80211` —— 必须**整体替换**内核栈。 |
| 固件加载 / SELinux | 内核无法从 `/data/local/tmp` 读取固件。 |

## 构建

```bash
# 1) 为你的 GKI 版本编译内核模块
./scripts/build_modules.sh        # -> cfg80211.ko, mac80211.ko, rtl8xxxu.ko
# 2) 编译静态用户态工具
./tools/build_tools.sh            # -> iw, aireplay-ng, airodump-ng, iwpriv
# 3) 打包并构建 APK
cp *.ko rtl8188fufw.bin iw deauth aireplay-ng airodump-ng app/assets/payload/
cd app && flutter build apk
```

## 使用（App）

1. **Prepare** —— 在 Magisk 弹窗授予 root；完成内核栈替换。
2. 插入 OTG 网卡 → **Detect**（出现 `wlan0`）。
3. **Test inject** —— 运行 `aireplay-ng -9`；应显示 *"Injection is working!"*。
4. **Scan** → 对**你自己拥有**的网络点击 **Deauth**。
5. **Restore** —— 重启即可恢复内置 WiFi。

## 许可证

采用 **GPL-2.0** —— 包含来自 `rtl8xxxu`/`mac80211`/`cfg80211`（Linux 内核）的修改代码。
