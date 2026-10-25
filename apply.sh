#!/usr/bin/env bash
# First-time installer for the AIC8800D80 USB Wi-Fi 6 adapter on NixOS.
# Copies the NixOS module into /etc/nixos, wires it into the config,
# switches, and loads the drivers. Idempotent: safe to re-run.
#
# Usage:  sudo bash apply.sh    (run from anywhere inside the repo)
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
MODULE_SRC="$SRC_DIR/nix/aic8800.nix"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0" >&2; exit 1; }
[ -f "$MODULE_SRC" ] || { echo "nix/aic8800.nix not found next to this script" >&2; exit 1; }

cp "$MODULE_SRC" /etc/nixos/modules/aic8800.nix
chmod 644 /etc/nixos/modules/aic8800.nix

# Import the module from modules/default.nix.
if ! grep -q './aic8800.nix' /etc/nixos/modules/default.nix; then
  sed -i 's|  imports = \[|  imports = [\n    ./aic8800.nix|' /etc/nixos/modules/default.nix
fi

# Enable it in configuration.nix: anchor on system.stateVersion, falling
# back to the last closing brace of the top-level attribute set.
if ! grep -q 'hardware.aic8800d80.enable' /etc/nixos/configuration.nix; then
  if grep -q '^  system.stateVersion = ' /etc/nixos/configuration.nix; then
    sed -i '/^  system.stateVersion = /a\
  # AIC8800D80 USB Wi-Fi 6 adapter\
  hardware.aic8800d80.enable = true;' /etc/nixos/configuration.nix
  else
    sed -i '$s|^}$|  # AIC8800D80 USB Wi-Fi 6 adapter\
  hardware.aic8800d80.enable = true;\
}|' /etc/nixos/configuration.nix
  fi
fi

nixos-rebuild switch

# Before the first reboot, plain modprobe only sees /run/booted-system;
# fall back to the freshly-switched module tree in that case.
load_mod () {
  modprobe "$1" 2>/dev/null || \
    modprobe -d /run/current-system/kernel-modules "$1"
}
load_mod aic_load_fw
load_mod aic8800_fdrv

sleep 5
echo '--- ip link ---'
ip link
