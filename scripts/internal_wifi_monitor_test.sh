#!/system/bin/sh
IW=/data/local/tmp/wifi/iw
setenforce 0
svc wifi disable
sleep 2
ip link set wlan0 down 2>&1
for w in /vendor_dlkm/lib/modules/qca_cld3_wlan.ko /vendor/lib/modules/qca_cld3_wlan.ko; do
  [ -e "$w" ] && WLANKO="$w"
done
echo "wlan.ko = $WLANKO"
echo "rmmod wlan..."; rmmod wlan 2>&1; echo "rmmod_rc=$?"
sleep 1
echo "lsmod wlan: $(lsmod | grep -c '^wlan')"
echo "insmod con_mode=4 ..."; insmod "$WLANKO" con_mode=4 2>&1; echo "insmod_rc=$?"
sleep 4
echo "con_mode now: $(cat /sys/module/wlan/parameters/con_mode 2>/dev/null)"
echo "--- dmesg ---"; dmesg | grep -iE 'wlan|con_mode|monitor|mon_|hdd' | tail -18
echo "--- iw dev ---"; $IW dev 2>&1 | grep -iE 'Interface|type'
echo "--- net ifaces ---"; ls /sys/class/net/ | grep -iE 'wlan|mon'
