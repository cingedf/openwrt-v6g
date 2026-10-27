#!/usr/bin/env bash
# Qihoo 360 V6G (mt7621 qihoo_360v6g) board overlay onto official OpenWrt v25.12.5.
# Same sparse-overlay pattern as cingedf/openwrt-rm2100-ipv4: no core source
# patches except registering the V6G case inside the ramips 02_network board
# script, plus sparse-config seed + custom DTS + appended Device block + UCI
# defaults overlay. Each build must always run in a pristine checkout.
set -Eeuo pipefail

log() { printf '[V6G] %s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"
[ -f "$GITHUB_WORKSPACE/config/v6g_minimal.config" ]               || die 'Missing sparse seed config'
[ -f "$GITHUB_WORKSPACE/dts/mt7621_qihoo_360v6g.dts" ]             || die 'Missing V6G device dts'
[ -f "$GITHUB_WORKSPACE/mt7621-qihoo-device.mk" ]                  || die 'Missing Device block append'
[ -f "$GITHUB_WORKSPACE/files/etc/uci-defaults/99-v6g-firstboot" ] || die 'Missing first-boot UCI defaults'
[ -f Makefile ] && [ -d target/linux/ramips ] || die 'Run from official OpenWrt source root'

ref="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
[ "$ref" = 'v25.12.5' ] || die "Expected official source tag v25.12.5, got '${ref:-untagged}'"

# 1) sparse config seed
cp "$GITHUB_WORKSPACE/config/v6g_minimal.config" .config

# 2) device tree source
cp "$GITHUB_WORKSPACE/dts/mt7621_qihoo_360v6g.dts" target/linux/ramips/dts/mt7621_qihoo_360v6g.dts

# 3) append Device/qihoo_360v6g image recipe to mt7621.mk
if grep -q 'Device/qihoo_360v6g' target/linux/ramips/image/mt7621.mk; then
  die 'Device/qihoo_360v6g already present in mt7621.mk'
fi
cat "$GITHUB_WORKSPACE/mt7621-qihoo-device.mk" >> target/linux/ramips/image/mt7621.mk

# 4) register the V6G port map inside the UPSTREAM ramips 02_network board
#    script. This goes here instead of an /etc/board.d/98-* override on
#    purpose: firstboot runs board.d scripts in lexical order and every
#    ucidef_set_interfaces_lan_wan() call APPENDS members to the /etc/board.json
#    "lan" ports array, so a late override leaves the generic catch-all's
#    phantom lan3/lan4 jacks in board.json forever (LuCI renders its Port
#    status cards straight from that file). One case branch, painted once:
net02='target/linux/ramips/base-files/etc/board.d/02_network'
grep -q 'qihoo,360v6g' "$net02" && die '02_network already has the V6G case'
python3 - "$net02" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path, encoding='utf-8').read()
branch = (
    '\tqihoo,360v6g)\n'
    '\t\tucidef_set_interfaces_lan_wan "lan1 lan2" "wan"\n'
    '\t\t;;\n'
)
anchor = '\t*)'
i = src.find(anchor)
assert i > 0, 'generic catch-all case not found in 02_network'
open(path, 'w', encoding='utf-8').write(src[:i] + branch + src[i:])
PYEOF
grep -F 'qihoo,360v6g)' "$net02" >/dev/null || die 'V6G case missing in patched 02_network'
grep -F 'ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"' "$net02" >/dev/null   || die 'V6G port map missing in patched 02_network'

# 5) rootfs overlay (uci-defaults applied at first boot)
mkdir -p files
cp -a "$GITHUB_WORKSPACE/files/." files/
chmod 0755 files/etc/uci-defaults/99-v6g-firstboot

log "Official OpenWrt ${ref} ($(git rev-parse --short=12 HEAD)) + qihoo_360v6g board overlay applied."
