# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="u-boot-RK3562"
PKG_VERSION="rg52mini-1.1"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/mamaich/u-boot-rk3562-rg52mini"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="U-Boot for the AISLPC RG52 Mini, with the splash, charge animation and power-off the vendor build lacks."
PKG_TOOLCHAIN="manual"

PKG_NEED_UNPACK="${PROJECT_DIR}/${PROJECT}/bootloader ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/bootloader"
PKG_NEED_UNPACK+=" ${PROJECT_DIR}/${PROJECT}/options ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/options"

# Sectors 64..16383 - primary loader, TPL, SPL and DDR init. Vendor code, taken
# from the EmuELEC dump as before: it never touches the display, it works, and
# replacing it is the one mistake that bricks the board.
PKG_AISLPC_BOOTLOADER_BASE="https://github.com/bmdhacks/aislpc-bootloader-tool/raw/main/devices/rg52mini/stock"

# The uboot partition itself - sector 16384, 4 MiB. Ours. The vendor U-Boot runs
# with the Rockchip evaluation-board device tree, twelve kilobytes with no dsi,
# panel, vop or route nodes, so it cannot put anything on the screen at all.
# This one shows the splash, runs the charge animation, lights the LED right
# after power is applied, powers the board off on request, and fixes up the
# device tree for revision A boards that have no Type-C controller.
PKG_RG52MINI_RELEASE="${PKG_SITE}/releases/download/${PKG_VERSION}/uboot-rg52mini.zip"

unpack() {
  mkdir -p ${PKG_BUILD}
  curl -fsSL -o ${PKG_BUILD}/bootloader_area.img \
    ${PKG_AISLPC_BOOTLOADER_BASE}/bootloader_area.img
  curl -fsSL -o ${PKG_BUILD}/uboot-rg52mini.zip \
    ${PKG_RG52MINI_RELEASE}
  unzip -q -o ${PKG_BUILD}/uboot-rg52mini.zip -d ${PKG_BUILD}/rg52mini
}

make_target() {
  : # nothing
}

makeinstall_target() {
  local uboot="${PKG_BUILD}/rg52mini/uboot.img"

  # Exactly 4 MiB, or it does not fit the partition and the tail of it would
  # land wherever the next one starts.
  if [ "$(stat -c%s "${uboot}")" != "4194304" ]; then
    die "${PKG_NAME}: uboot.img is $(stat -c%s "${uboot}") bytes, expected 4194304"
  fi

  # Pre-partition blob for the final dd seek=64:
  #   source sector 64   -> blob sector 0     -> disk sector 64 (idbloader / SPL)
  #   blob sector 16320  -> disk sector 16384 (U-Boot FIT, 4 MiB)
  # The source is a dump of disk sectors 0-16383, so skip its first 64 sectors.
  truncate -s $((32704 * 512)) ${PKG_BUILD}/uboot.bin
  dd if=${PKG_BUILD}/bootloader_area.img \
    of=${PKG_BUILD}/uboot.bin \
    bs=512 skip=64 count=16320 conv=fsync,notrunc status=none
  dd if=${uboot} \
    of=${PKG_BUILD}/uboot.bin \
    bs=512 seek=16320 conv=fsync,notrunc status=none

  # The splash and the charge animation frames. This bootloader reads them as
  # plain files from the bootable partition - the resource partition on this
  # device is empty - so mkimage puts them at the root of the boot FAT.
  # 24-bit BMP, uncompressed: the vendor frames are 8-bit RLE and this
  # bootloader silently refuses to draw those.
  #
  # logo_kernel.bmp is deliberately not among them. That file is handed to the
  # kernel so the picture survives the handover, and on this device the
  # handover blanks the panel: boot carries on normally, the screen goes dark
  # the moment the system reaches the display.
  mkdir -p ${PKG_BUILD}/bmp
  cp -a ${PKG_BUILD}/rg52mini/bmp/*.bmp ${PKG_BUILD}/bmp/
}
