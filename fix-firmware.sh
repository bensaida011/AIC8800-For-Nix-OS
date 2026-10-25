#!/usr/bin/env bash
# Re-apply the current nix/aic8800.nix to the system and reload the
# drivers. Use after editing the module (new driver pin, patches,
# firmware changes). Idempotent and safe to re-run.
#
# Usage:  sudo bash fix-firmware.sh    (run from anywhere inside the repo)
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
MODULE_SRC="$SRC_DIR/nix/aic8800.nix"
FW_PATH_ARG="aic_fw_path=/run/current-system/firmware/aic8800D80"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0" >&2; exit 1; }
[ -f "$MODULE_SRC" ] || { echo "nix/aic8800.nix not found next to this script" >&2; exit 1; }

cp "$MODULE_SRC" /etc/nixos/modules/aic8800.nix
chmod 644 /etc/nixos/modules/aic8800.nix

nixos-rebuild switch

# Unbind whatever the old aic_load_fw owns, then swap the modules.
for i in /sys/bus/usb/drivers/aic_load_fw/*:*/; do
  n=${i%/}; n=${n##*/}
  echo "unbinding $n"
  echo "$n" > /sys/bus/usb/drivers/aic_load_fw/unbind || true
done
rmmod aic8800_fdrv 2>/dev/null || true
rmmod aic_load_fw 2>/dev/null || true

# Plain modprobe works once booted into a generation that has the module;
# before that (same-boot switch) fall back to the new module tree.
load_mod () {
  if [ "$1" = aic_load_fw ]; then
    modprobe aic_load_fw "$FW_PATH_ARG" 2>/dev/null || \
      modprobe -d /run/current-system/kernel-modules aic_load_fw "$FW_PATH_ARG"
  else
    modprobe aic8800_fdrv 2>/dev/null || \
      modprobe -d /run/current-system/kernel-modules aic8800_fdrv
  fi
}
load_mod aic_load_fw
load_mod aic8800_fdrv

# Registering the driver auto-probes already-attached dongles; bind
# explicitly if any a69c device is still unclaimed.
sleep 1
for d in /sys/bus/usb/devices/*:1.0; do
  if [ -f "$d/modalias" ] && grep -qi 'usb:vA69C' "$d/modalias" 2>/dev/null; then
    echo "${d##*/}" > /sys/bus/usb/drivers/aic_load_fw/bind 2>/dev/null || true
  fi
done

sleep 8
echo '--- ip link ---'
ip link
echo '--- kernel log ---'
dmesg | grep -iE 'aic|fmacfw|fw_patch' | tail -25
