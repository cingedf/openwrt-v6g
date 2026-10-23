
define Device/qihoo_360t6gs
  $(Device/nand)
  $(Device/uimage-lzma-loader)
  DEVICE_VENDOR := Qihoo
  DEVICE_MODEL := 360 V6G
  DEVICE_DTS := mt7621_qihoo_360t6gs
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 40960k
  IMAGES += factory.bin
  IMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-ubi | \
	check-size
  DEVICE_PACKAGES := kmod-mt7915-firmware kmod-usb3 kmod-usb-ledtrig-usbport
endef
TARGET_DEVICES += qihoo_360t6gs
