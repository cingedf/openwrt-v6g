# openwrt-v6g

Dedicated OpenWrt v25.12.5 cloud build for the **Qihoo 360 V6G** (MT7621AT, 128 MiB NAND, MT7915 WiFi, MT7530 DSA with exactly 2 LAN jacks + 1 WAN jack, USB, tri-color sys LED, Reset + 360 mesh-paring button).

This is not a port of a sibling board: the board identity, DTS, port map and NAND layout below are all derived from the real V6G hardware (RAM-image jack-by-jack cable walk, on-wire MAC checks, partition dumps).

Follows the minimal-overlay pattern of `cingedf/openwrt-rm2100-ipv4`: official OpenWrt source is cloned at build time; this repository injects only:

- `config/v6g_minimal.config` — sparse seed config (PPPoE main-router + direct-drive mihomo proxy gateway; ShellCrash shell framework NOT used)
- `dts/mt7621_qihoo_360v6g.dts` — device tree: board id `qihoo,360v6g`, 2 LAN + 1 WAN DSA ports, USB xhci, factory nvmem EEPROM/MAC, layout v2
- `mt7621-qihoo-device.mk` — `Device/qihoo_360v6g` recipe appended to the official `mt7621.mk`
- `files/etc/uci-defaults/99-v6g-firstboot` — first-boot defaults (LAN 192.168.123.1, port/bridge sanity, CN wireless country, LED service, ZRAM, root password)
- `files/etc/init.d/mihomo-v6g` — procd init that direct-drives the mihomo core (`/etc/ShellCrash/CrashCore`) with respawn; loads the independent nft tproxy table and fwmark plumbing itself (no ShellCrash start.sh — that path caused a busybox fork storm)
- `files/etc/nftables-mihomo.nft` — independent `table inet mihomo` prerouting tproxy rules (survives fw4 reload; fake-ip range intentionally not skipped)
- `files/etc/sysctl.d/15-v6g-memory` — `vm.swappiness=15` for the proxy-core RAM workload
- `files/usr/sbin/v6g-mihomo-wiring` — idempotent wiring helper: preconditions, service refresh, dnsmasq → mihomo fake-ip DNS (+ safety net), swappiness migration, zram zstd switch (only if the kernel actually has the backend), end-to-end smoke test
- `diy-part2.sh` — overlays the above, registers the V6G case inside the upstream ramips `02_network` (see why below), AND patches one core kernel-config line into the ramips `config-6.12`: `CONFIG_ZRAM_BACKEND_ZSTD=y` (zram zstd backend for the proxy workload; OpenWrt has no package-level symbol for it, and the build Assert step verifies the line survived defconfig)
- `config` also enables `luci-proto-ppp` + `luci-i18n-base-zh-cn` — the base-router bring-up kit so PPPoE dial-up and the Chinese web UI are hand-configurable in LuCI

## Base bring-up path (what a fresh image can and cannot do out of the box)

Boot fresh `factory.bin` once and the box is already a working CN main router
except for the two operator knobs (dial-up + WiFi key):

1. Modem/ONT → **wan** jack (middle bottom port), PC → lan1/lan2.
2. LuCI at `http://192.168.123.1` SSH `root`/`password`.
3. System → Language: 简体中文 (i18n zh-cn package included).
4. Network → Interfaces → WAN → Protocol **PPPoE** → ISP account + password → save & apply. (`luci-proto-ppp` provides this page.)
5. Network → Wireless → both SSIDs (`Redmi_579E_2.4` / `Redmi_579E`) ship **open** on purpose for first contact — set WPA2 key immediately.
6. Sys LED goes **green solid** when the WAN link is up (red solid = no internet; the v6g-led service watches the default route).

Deliberate base-only decisions (all reversible via uci):

- **IPv6 off at first boot**: stock `wan6` stub is removed by `99-v6g-firstboot`; the proxy layer is IPv4-only and any v6 prefix would bypass the mihomo tproxy path. To re-enable: re-create `wan6` + offer RA/DHCPv6 on lan.
- **NTP pinned to CN servers** (223.5.5.5, cn.pool.ntp.org) — REALITY handshakes depend on a sane clock.
- **Proxy layer dormant**: `mihomo-v6g` init/nft/sysctl/wiring files ship but nothing is enabled; no mihomo runs at all until the operator deploys the core binary (`/etc/ShellCrash/CrashCore` + `configs/config.yaml`) and runs `/usr/sbin/v6g-mihomo-wiring`. The image alone never dials the proxy.

## Why the port map is patched in `02_network`

Every board.d script runs in lexical order at first boot and each
`ucidef_set_interfaces_lan_wan()` call **appends** members to the
`/etc/board.json` `network.lan.ports` array — it never replaces them. The
generic ramips catch-all paints `lan1 lan2 lan3 lan4`, so a late override
file always leaves phantom lan3/lan4 entries (and duplicated lan1/lan2)
inside `/etc/board.json`; LuCI's Port status page reads that file directly,
which is why phantom jacks used to survive even a "correct" uci-side config.
The V6G case is therefore inserted **before** the catch-all inside the
upstream `02_network` itself: one case branch, painted once, board.json ends
up with `ports: [lan1, lan2]` and `wan` only.

## NAND layout v2 (theory matches live device checks)

| offset    | size    | label        | role |
|-----------|---------|--------------|------|
| 0x0000000 | 512k    | `u-boot`     | DragonBluep boot loader — **absolutely never erased/rewritten by this flow**; byte-verified against the shipped `u-boot-mt7621.bin` |
| 0x080000  | 256k    | `u-boot-env` | DragonBluep env storage — currently CRC-invalid stock residue (~3 strings); u-boot falls back to its built-in default env every boot, so this block is inert either way and left untouched |
| 0x0c0000  | 256k    | `factory`    | stock calibration block; `eeprom@0` (0..0xe00) feeds MT7915 EEPROM + MACs (both radios verified on-wire), tail of the block is all-FF — **absolutely never erased** |
| 0x100000  | 41 MiB  | `storage`    | merged bare block: former stock `Config`/`config`/`factory2`/`plugin`/`log` partitions, barely any data inside and **not mounted by OpenWrt**; this flow never erases it — kept as an untouched stock-residue parking lot |
| 0x2a00000 | 84 MiB  | `firmware`   | our OpenWrt: child `kernel` (4 MiB, **absolute offset 0x2a00000, must not move**) + child `ubi` (82 MiB, `rootfs` squashfs + `rootfs_data` autoresize → ~63 MiB mounted overlay) |

Every offset/size is a multiple of the 128 KiB erase block; `0x2a00000 + 0x5600000 = 0x8000000` — `firmware` ends exactly at the 128 MiB flash boundary.

## Artifacts

| file | use |
|---|---|
| `qihoo_360v6g-initramfs-kernel.bin` | RAM-only verification boot (bootloader WebUI / TFTP `recovery.bin`) |
| `qihoo_360v6g-factory.bin` | persistent image: 4 MiB kernel (pad-to) + appended ubi, **flashed into `firmware` at absolute 0x2a00000** |
| `qihoo_360v6g-sysupgrade.bin` | in-system upgrade from a running OpenWrt (fwtool-stripped header, produces same layout) |
| `*.manifest`, `config.buildinfo`, feeds/version dumps | build metadata |

## Flashing

Bootloader-side notes (WebUI failsafe, TFTP recovery, serial U-Boot console) treat the
image the same regardless of today's board id, because the kernel child offset did not move.

1. RAM verification: hold Reset while powering on, release after ~5 LED blinks → bootloader WebUI at `http://192.168.1.1` → upload `initramfs-kernel.bin`.
2. Persistent: same recovery → upload `factory.bin`.
3. From a running OpenWrt: LuCI → System → Flash new firmware → `sysupgrade.bin`, or SSH `sysupgrade /tmp/...`.
4. Serial (115200): `u-boot-env` is inert, so set the network up at runtime `setenv serverip 192.168.1.2; setenv ipaddr 192.168.1.1; setenv netmask 255.255.255.0` (no `saveenv`) → `tftpboot 84000000 factory.bin` → verify `crc32 84000000 <size>` against the locally computed zlib crc32 → `nand erase 0x2a00000 0x5600000` → `nand write 84000000 0x2a00000 <size>` → readback `nand read` + `crc32` → `reset`.

Alternative in-system full rewrite (works from any OpenWrt with `mtd`):

    mtd -e firmware write /tmp/factory.bin firmware   # then verify: mtd verify /tmp/factory.bin firmware

## Boot-chain invariants (do not break)

- `kernel` child absolutely at 0x2a00000 — the bootloader's hard-coded load offset.
- `u-boot` and `factory` before 0x100000 stay untouched — MT7915 EEPROM + MACs come from there.
- The `ubi` child depends only on the `kernel`/`ubi` offsets inside `firmware`; the WebUI/TFTP/serial recovery paths keep working.
- `factory.bin` = `append-kernel` `pad-to 4096k` `append-ubi` with `IMAGE_SIZE 88064k`; changing `KERNEL_SIZE` requires resizing the DTS `kernel` child to match.

## Restoration

Stock 2669 firmware backups: per-partition `mtd0..mtd12` bins + `full_mtd.bin`
(byte-accurate 0x0..0x7a00000; the 6 MiB tail was never partitioned by stock).
Rollback writes stock bins back over this layout through the bootloader or a
full-NAND restore.
