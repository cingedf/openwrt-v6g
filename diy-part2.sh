#!/usr/bin/env bash
# Qihoo 360 V6G (mt7621 qihoo_360v6g) board overlay onto official OpenWrt v25.12.5.
# Same sparse-overlay pattern as cingedf/openwrt-rm2100-ipv4: no core source
# patches except registering the V6G case inside the ramips 02_network board
# script, plus sparse-config seed + custom DTS + appended Device block + UCI
# defaults overlay + ONE core-kernel-config line (CONFIG_ZRAM_BACKEND_ZSTD,
# there is no package-level symbol for it). Each build must always run in a
# pristine checkout.
set -Eeuo pipefail

log() { printf '[V6G] %s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"
[ -f "$GITHUB_WORKSPACE/config/v6g_minimal.config" ]               || die 'Missing sparse seed config'
[ -f "$GITHUB_WORKSPACE/dts/mt7621_qihoo_360v6g.dts" ]             || die 'Missing V6G device dts'
[ -f "$GITHUB_WORKSPACE/mt7621-qihoo-device.mk" ]                  || die 'Missing Device block append'
[ -f "$GITHUB_WORKSPACE/files/etc/uci-defaults/99-v6g-firstboot" ] || die 'Missing first-boot UCI defaults'
[ -f "$GITHUB_WORKSPACE/files/etc/init.d/mihomo-v6g" ]             || die 'Missing direct-drive mihomo init script'
[ -f "$GITHUB_WORKSPACE/files/etc/nftables-mihomo.nft" ]           || die 'Missing mihomo nft tproxy table'
[ -f "$GITHUB_WORKSPACE/files/etc/sysctl.d/15-v6g-memory" ]        || die 'Missing memory-tuning sysctl'
[ -f "$GITHUB_WORKSPACE/files/usr/sbin/v6g-mihomo-wiring" ]        || die 'Missing mihomo wiring helper'
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
#    status cards straight from that file). One case branch, painted once.
#    Upstream moved the file into a per-subtarget dir for v25.x
#    (target/linux/ramips/mt7621/base-files/...) while v24.x still keeps the
#    target-level path; resolve whichever exists so the script survives both.
for cand in \
    'target/linux/ramips/mt7621/base-files/etc/board.d/02_network' \
    'target/linux/ramips/base-files/etc/board.d/02_network'
do
  [ -f "$cand" ] && net02="$cand" && break
done
[ -n "${net02:-}" ] || die '02_network not found (neither v25 subtarget nor v24 target path)'
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

# 4b) Enable the zram zstd compression backend as a CORE kernel option. The 6.12
#     zram driver gates its backends behind CONFIG_ZRAM_BACKEND_* booleans and
#     only lzo/lzo-rle default to on; OpenWrt has no package-level symbol for it,
#     so the kernel config is patched directly (idempotent). NOTE: since the
#     v25.12.x layout the per-subtarget config lives in the subtarget folder
#     (target/linux/ramips/mt7621/config-6.12); the generic config is not touched.
#     First-boot comp algo stays lzo (safe on kernels built before this line);
#     v6g-mihomo-wiring flips uci zram_comp_algo to zstd only after verifying the
#     backend is actually visible in the running kernel.
kcfg=target/linux/ramips/mt7621/config-6.12
[ -f "$kcfg" ] || die "kernel config not found: $kcfg (not a ramips mt7621 6.12 tree?)"
python3 - "$kcfg" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding='utf-8').read().splitlines()
lines = [l for l in lines if not l.startswith('CONFIG_ZRAM_BACKEND_ZSTD')]
lines.append('# V6G: zram zstd backend for the proxy-core workload (R3 memory tuning)')
lines.append('CONFIG_ZRAM_BACKEND_ZSTD=y')
open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
PYEOF
grep -Fq 'CONFIG_ZRAM_BACKEND_ZSTD=y' "$kcfg" || die 'ZRAM_BACKEND_ZSTD patch failed'

# 5) rootfs overlay (uci-defaults applied at first boot)
mkdir -p files
cp -a "$GITHUB_WORKSPACE/files/." files/
chmod 0755 files/etc/uci-defaults/99-v6g-firstboot
chmod 0755 files/etc/init.d/mihomo-v6g
chmod 0755 files/usr/sbin/v6g-mihomo-wiring

log "Official OpenWrt ${ref} ($(git rev-parse --short=12 HEAD)) + qihoo_360v6g board overlay applied."
