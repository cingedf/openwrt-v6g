#!/usr/bin/env bash
# Qihoo 360 V6G (mt7621 qihoo_360t6gs) board overlay onto official OpenWrt v25.12.5.
# Following the cingedf/openwrt-rm2100-ipv4 pattern: no core source patches,
# only sparse-config seed + custom DTS + appended Device block + UCI defaults overlay.
set -Eeuo pipefail

log() { printf '[V6G] %s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"
[ -f "$GITHUB_WORKSPACE/config/v6g_minimal.config" ]          || die 'Missing sparse seed config'
[ -f "$GITHUB_WORKSPACE/dts/mt7621_qihoo_360t6gs.dts" ]       || die 'Missing V6G device dts'
[ -f "$GITHUB_WORKSPACE/mt7621-qihoo-device.mk" ]             || die 'Missing Device block append'
[ -f "$GITHUB_WORKSPACE/files/etc/uci-defaults/99-v6g-firstboot" ] || die 'Missing first-boot UCI defaults'
[ -f Makefile ] && [ -d target/linux/ramips ] || die 'Run from official OpenWrt source root'

ref="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
[ "$ref" = 'v25.12.5' ] || die "Expected official source tag v25.12.5, got '${ref:-untagged}'"

# 1) sparse config seed
cp "$GITHUB_WORKSPACE/config/v6g_minimal.config" .config

# 2) device tree source
cp "$GITHUB_WORKSPACE/dts/mt7621_qihoo_360t6gs.dts" target/linux/ramips/dts/mt7621_qihoo_360t6gs.dts

# 3) append Device/qihoo_360t6gs image recipe to mt7621.mk
if grep -q 'Device/qihoo_360t6gs' target/linux/ramips/image/mt7621.mk; then
  die 'Device/qihoo_360t6gs already present in mt7621.mk'
fi
cat "$GITHUB_WORKSPACE/mt7621-qihoo-device.mk" >> target/linux/ramips/image/mt7621.mk

# 4) rootfs overlay (uci-defaults applied at first boot)
mkdir -p files
cp -a "$GITHUB_WORKSPACE/files/." files/
chmod 0755 files/etc/uci-defaults/99-v6g-firstboot

log "Official OpenWrt ${ref} ($(git rev-parse --short=12 HEAD)) + qihoo_360t6gs board overlay applied."
