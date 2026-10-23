
define Device/qihoo_360t6gs
  $(Device/nand)
  $(Device/uimage-lzma-loader)
  DEVICE_VENDOR := Qihoo 360
  DEVICE_MODEL := V6G
  DEVICE_DTS := mt7621_qihoo_360t6gs
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 86016k
  IMAGES += factory.bin
  IMAGE/factory.bin := append-kernel | pad-to $$$$(KERNEL_SIZE) | append-rootfs | pad-rootfs | check-size | append-metadata
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-mt7915-firmware kmod-usb3 kmod-usb-ledtrig-usbport -uboot-envtools
endef
TARGET_DEVICES += qihoo_360t6gs
