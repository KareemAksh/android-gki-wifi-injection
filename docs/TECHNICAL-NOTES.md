# Technical notes

Field notes from the build — the non-obvious parts, with the actual evidence.

## 1. Confirming unsigned out-of-tree modules can load

`CONFIG_MODULE_SIG=y` and `CONFIG_MODULE_SIG_PROTECT=y` looked like a blocker, but `CONFIG_MODULE_SIG_FORCE` is **not** set. Proof that unsigned OOT modules already load on the running kernel — `/proc/sys/kernel/tainted`:

```
13824 = 8192 (TAINT_UNSIGNED_MODULE) + 4096 (TAINT_OOT_MODULE) + 1024 (TAINT_CRAP) + 512 (TAINT_WARN)
```

Bit 13 set ⇒ an unsigned module is already loaded ⇒ ours will too.

## 2. Matching vermagic on a GKI kernel

vermagic must equal the running kernel's exactly:

```
5.15.178-android13-8-00021-g6f2f96be86b9-ab13729987 SMP preempt mod_unload modversions aarch64
```

A git-archive checkout has no SCM info, so `setlocalversion` yields just `5.15.178`. Putting the suffix in `.scmversion` reproduces the full string:

```
echo '-android13-8-00021-g6f2f96be86b9-ab13729987' > .scmversion
```

`vmlinux.symvers` from the GKI build (`ci.android.com/builds/submitted/<bid>/kernel_aarch64/latest/raw/vmlinux.symvers`) supplies the core symbol CRCs for `MODVERSIONS`.

## 3. Full LTO + CFI + SCS ⇒ Clang only

```
CONFIG_LTO_CLANG_FULL=y   CONFIG_CFI_CLANG=y   (not permissive)   CONFIG_SHADOW_CALL_STACK=y
```

The kernel calls module function pointers (e.g. `net_device_ops`); a non-CFI module would trap → panic. So modules must be built with the same Clang major (14) and `LLVM=1` so Kbuild applies LTO/CFI/SCS. Upstream LLVM 14.0.0 has the same CFI/LTO ABI as AOSP clang r450784e (14.0.7).

## 4. Why `mac80211` won't bind the *vendor* `cfg80211`

The loaded `cfg80211` is a Qualcomm OOT module (`vermagic 5.15.94`). Comparing exported symbol CRCs (`nm … | grep __crc_`) against a stock build:

```
of the 92 cfg80211 symbols mac80211 imports:  69 DIFF  /  23 MATCH
```

Module↔module CRCs are **not** part of the frozen KMI, so they diverge from stock ACK regardless of sublevel or `CONFIG_CFG80211_WEXT`. Conclusion: you cannot bind a stock-built `mac80211` to the vendor `cfg80211`, and you cannot load a *second* `cfg80211` (`nl80211` genl family is a singleton). ⇒ **swap the whole stack** (load our `cfg80211`+`mac80211`+`rtl8xxxu`, after unloading the vendor stack), which is consistent end-to-end and reversible.

Smoke test that isolates the issue (loading our mac80211 against the vendor cfg80211):

```
mac80211: disagrees about version of symbol cfg80211_tdls_oper_request
mac80211: Unknown symbol cfg80211_reg_can_beacon_relax (err -22)
```

— errors only on cfg80211 symbols; no vermagic/core-symbol errors ⇒ the module itself is correct.

## 5. Backporting 8188F (6.6 → 5.15)

Compiling the 6.6 `rtl8xxxu` against 5.15 headers produced ~20 errors in two API families:

- **MLO split (6.4+):** `sta->deflink.{ht_cap,vht_cap,supp_rates}` → `sta->…`  (`sed 's/->deflink\././g'`)
- **vif cfg (6.x):** `vif->cfg.{assoc,aid}` → `vif->bss_conf.…`
- **`ieee80211_ops` shims:** `bss_info_changed` `u64 changed`→`u32`; `start_ap` drop `bss_conf` arg; `conf_tx` drop `link_id`; `ieee80211_beacon_get(hw,vif,0)`→`(hw,vif)`; drop `.wake_tx_queue = ieee80211_handle_wake_tx_queue`.

## 6. Embedded firmware (SELinux)

`request_firmware()` from `/data/local/tmp` fails:

```
loading /data/local/tmp/wifi/fw/rtlwifi/rtl8188fufw.bin failed with error -13   (EACCES, SELinux)
```

Fix: compile the 21 KB `rtl8188fufw.bin` into the module as a C array and short-circuit the load for that name. Result: `Firmware revision 4.0 (signature 0x88f1)` with no filesystem dependency.

## 7. Internal Qualcomm WiFi: monitor yes, injection no

`con_mode` is a load-time module param. Reloading with `con_mode=4`:

```
__hdd_mon_open: hdd_start_adapters() successful !   →   wlan0  type monitor
```

Channel can't be set via `iw` (driver returns `Operation not permitted`); it requires the proprietary private ioctl `iwpriv wlan0 setMonChan <ch> <bw>`. But the firmware monitor path is **capture-only** — `setMonChan` begins timing out and `aireplay-ng -9` injects nothing. Qualcomm phone firmware does not support TX injection in monitor mode. (Also observed: Magisk's adb-`su` capability set is inconsistent across calls — `CapEff` sometimes `0` — which independently blocks `socket(PF_PACKET)`.)
