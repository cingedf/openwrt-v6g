# openwrt-v6g

Official OpenWrt v25.12.5 cloud build for **Qihoo 360 V6G** (MT7621AT, S34ML01G2 128MiB NAND, MT7915/7916 WiFi, MT7530 DSA with 3 LAN + 1 WAN, USB, tri-color sys LED, Reset + 360组网 buttons).

Follows the minimal-overlay pattern of `cingedf/openwrt-rm2100-ipv4`: official OpenWrt source is cloned at build time; this repository injects only:

- `config/v6g_minimal.config` — sparse seed config
- `dts/mt7621_qihoo_360t6gs.dts` — device tree (3 LAN + WAN, USB xhci, factory nvmem MAC/EEPROM, firmware partition at 0x2A00000)
- `mt7621-qihoo-device.mk` — `Device/qihoo_360t6gs` recipe appended to the official `mt7621.mk`
- `files/etc/uci-defaults/99-v6g-firstboot` — first-boot defaults (LAN 192.168.123.1, ports list, CN wireless country)
- `diy-part2.sh` — overlays the above into the official source tree

## Build

Actions → `Build Qihoo 360 V6G (360t6gs) - OpenWrt 25.12.5` → Run workflow.

Artifacts:

| file | use |
|---|---|
| `qihoo_360t6gs-initramfs-kernel.bin` | RAM-only verification boot (DragonBluep WebUI /flashing) |
| `qihoo_360t6gs-factory.bin` | persistent image: kernel + squashfs rootfs, flashed by DragonBluep recovery at 0x2A00000 |
| `qihoo_360t6gs-sysupgrade.bin` | in-system upgrade from ImmortalWrt/OpenWrt |
| `*.manifest`, config dumps | build metadata |

## Flashing

1. RAM verification: hold Reset while powering on, release after ~5 LED blinks → DragonBluep WebUI at `http://192.168.1.1` → upload `initramfs-kernel.bin`.
2. Persistent: same recovery → upload `factory.bin`.
3. From a running OpenWrt/ImmortalWrt: luci → System → Flash new firmware → `sysupgrade.bin`.

## Restoration

Original vendor 2669 firmware backup: `Desktop\router_backup\mtd8_firmware.bin` (md5-verified, byte-accurate).
