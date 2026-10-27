# openwrt-v6g

Official OpenWrt v25.12.5 cloud build for **Qihoo 360 V6G** (MT7621AT, S34ML01G2 128MiB NAND, MT7915/7916 WiFi, MT7530 DSA with 3 LAN + 1 WAN, USB, tri-color sys LED, Reset + 360组网 buttons).

Follows the minimal-overlay pattern of `cingedf/openwrt-rm2100-ipv4`: official OpenWrt source is cloned at build time; this repository injects only:

- `config/v6g_minimal.config` — sparse seed config
- `dts/mt7621_qihoo_360t6gs.dts` — device tree (3 LAN + WAN, USB xhci, factory nvmem MAC/EEPROM, layout v2)
- `mt7621-qihoo-device.mk` — `Device/qihoo_360t6gs` recipe appended to the official `mt7621.mk`
- `files/etc/uci-defaults/99-v6g-firstboot` — first-boot defaults (LAN 192.168.123.1, ports list, CN wireless country)
- `files/etc/board.d/98-qihoo-360t6gs` — port-map override (lan1 lan2 = lan, wan), fixes the stock ramips `02_network` fallback painting phantom lan3/lan4 ports
- `diy-part2.sh` — overlays the above into the official source tree (asserts every injected file exists)

## NAND layout v2 (theory matches live device checks)

| offset    | size   | label       | role |
|-----------|--------|-------------|------|
| 0x0000000 | 512k   | `u-boot`    | DragonBluep boot loader — **absolutely never erased/rewritten by this flow**; byte-verified against the shipped `u-boot-mt7621.bin` |
| 0x080000  | 256k   | `u-boot-env`| DragonBluep env storage — **currently CRC-invalid stock residue** (`serverip=192.168.0.100 / ipaddr=192.168.0.12 / ethaddr=00:AA:BB:CC:DD:10`); u-boot falls back to its built-in default env every boot, `saveenv` has never been executed |
| 0x0c0000  | 256k   | `factory`   | stock calibration block; `eeprom@0` (0..0xe00) feeds MT7915 EEPROM + MACs (`00:0c:43:26:46:30`/`.59:31`, verified on-wire), tail of the block is all-FF — **absolutely never erased** |
| 0x100000  | 41 MiB | `storage`   | layout v2 merged block: former stock `Config`(256k, all-FF) + `config`(512k, ~9KB stock crumbs) + `factory2`(256k, ~150B) + `plugin`(36MiB, ~200KB OTA leftovers) + `log`(4MiB, ~550KB stock logs). **Bare MTD, not mounted by OpenWrt; this flow never erases it** — the few hundert KB of stock residue inside stays untouched and harmless |
| 0x2a00000 | 84 MiB | `firmware`  | our OpenWrt: child `kernel` (4 MiB, **absolute offset 0x2a00000, must not move** — DragonBluep `CONFIG_DEFAULT_NAND_KERNEL_OFFSET`) + child `ubi` (82 MiB, `rootfs` squashfs + `rootfs_data` autoresize → ~75 MiB writable overlay) |

Every offset/size is a multiple of the 128 KiB erase block; `0x2a00000 + 0x5600000 = 0x8000000` — `firmware` ends exactly at the 128 MiB flash boundary. Flash area beyond the raw 122 MiB stock backup (0x7a00000..0x8000000, the 6 MiB tail) was never partitioned by the stock layout either, so it is empty flash that layout v2 claims for `firmware`.

## Artifacts

| file | use |
|---|---|
| `qihoo_360t6gs-initramfs-kernel.bin` | RAM-only verification boot (DragonBluep WebUI / TFTP `recovery.bin`) |
| `qihoo_360t6gs-factory.bin` | persistent image: 4 MiB kernel (pad-to) + ubi with squashfs, **flashed into `firmware` at absolute 0x2a00000** |
| `qihoo_360t6gs-sysupgrade.bin` | in-system upgrade from a running OpenWrt (fwtool-stripped header, produces same layout) |
| `*.manifest`, config dumps | build metadata |

## Flashing

1. RAM verification: hold Reset while powering on, release after ~5 LED blinks → DragonBluep WebUI at `http://192.168.1.1` → upload `initramfs-kernel.bin`.
2. Persistent: same recovery → upload `factory.bin`.
3. From a running OpenWrt/ImmortalWrt: LuCI → System → Flash new firmware → `sysupgrade.bin`.
4. Serial (COM3, 115200): 1s `"Hit any key to stop autoboot"` window / `*** U-Boot Boot Menu ***` → U-Boot console. Because `u-boot-env` carries no valid net config, run `setenv serverip 192.168.1.2; setenv ipaddr 192.168.1.1; setenv netmask 255.255.255.0` (runtime-only, no `saveenv` needed) before `tftpboot 84000000 factory.bin`; validate `crc32` against the local zlib-crc32 of the file, then `nand erase 0x2a00000 0x5600000` + `nand write 84000000 0x2a00000 <size>` + readback `crc32` before `reset`.

## Boot-chain invariants (do not break)

- `kernel` child absolutely at 0x2a00000 — U-Boot's hard-coded load offset.
- `factory` before 0x100000 untouched — MT7915 EEPROM + MACs come from there.
- ubi child layout depends only on the `kernel`/`ubi` child offsets inside `firmware`, not on U-Boot's own mtdparts table, so stock U-Boot menu/WebUI/TFTP recovery paths all keep working.
- `factory.bin` = `append-kernel | pad-to 4096k | append-ubi` with `IMAGE_SIZE 88064k`; changing `KERNEL_SIZE` requires locking it with the DTS `kernel` child size (both 0x400000 today).

## Restoration

Stock 2669 firmware backup: `Desktop\360V6G\V6G备份\` — `mtd0..mtd12` per-partition bins + `full_mtd.bin` (byte-accurate 0x0..0x7a00000; the unwrapped 6 MiB tail was never partitioned by stock). Rollback path writes the stock bins back over this layout via DragonBluep U-Boot or a full-NAND restore.
