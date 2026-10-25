# AIC8800D80 USB Wi-Fi 6 adapter (aicsemi a69c:5721 -> a69c:8d80) support.
#
# - aic8800d80 out-of-tree kernel driver (aic_load_fw + aic8800_fdrv)
# - firmware blobs loaded by aic_load_fw from /lib/firmware/aic8800*
# - udev rule that switches the dongle out of its "driver CD" USB mass
#   storage mode as soon as it is plugged in
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.aic8800d80;

  aic8800-src = pkgs.fetchFromGitHub {
    owner = "shenmintao";
    repo = "aic8800d80";
    # legacy-mcu1 branch: required for chip_id=7/chip_mcu_id=1 hardware
    # (main branch fails with a deterministic upload stall at 0x170400).
    rev = "a9683a456079131a0381ed75fb7a4f5514527b3c";
    hash = "sha256-yK71pZuw8H2JpidoexrrmkJ/puoxkN36gHtpMf+QZxU=";
  };

  aic8800-firmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "aic8800-firmware";
    version = "1.0.0";
    src = aic8800-src;
    sourceRoot = "source/fw";
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/firmware
      cp -r . $out/lib/firmware/
      runHook postInstall
    '';
    # The driver opens firmware files directly with kernel file reads
    # (CONFIG_USE_FW_REQUEST=n), so the blobs must NOT be zstd-compressed
    # the way hardware.firmware compresses every package by default.
    passthru.compressFirmware = false;
  };

  aic8800-kmodule = config.boot.kernelPackages.callPackage ({ stdenv, lib, kmod, kernel, kernelModuleMakeFlags }:
    stdenv.mkDerivation {
      pname = "aic8800";
      version = "1.0.0";
      src = aic8800-src;
      sourceRoot = "source/drivers/aic8800";
      hardeningDisable = [ "all" ];
      nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;
      enableParallelBuilding = true;
      makeFlags = kernelModuleMakeFlags ++ [
        "KVER=${kernel.modDirVersion}"
        "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      ];
      # Route installation through the kernel's modules_install instead of
      # the vendor Makefile's file copy: this runs the module signing rule
      # (kmodigest), producing the .ko.cer files the NixOS module tree
      # build concatenates into modules.cer. The appended target is invoked
      # by the default install phase through installTargets, which passes
      # makeFlags (incl. cmd_sign) as proper argv entries.
      postPatch = ''
        # NixOS has no /lib/firmware; firmware lives behind the
        # /run/current-system/firmware symlink (and NixOS points the
        # kernel's firmware_class.path at a store path instead). The
        # driver opens firmware files directly, so it needs a real path.
        substituteInPlace aic_load_fw/aicbluetooth.c \
          --replace '"/lib/firmware"' '"/run/current-system/firmware"'
        printf 'aic_install:\n\tmake -C $(KDIR) M=$(PWD) modules_install INSTALL_MOD_PATH=$(INSTALL_MOD_PATH)\n' >> Makefile
      '';
      installTargets = [ "aic_install" ];
      installFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
      # depmod metadata would collide with the kernel's own modules tree
      # when boot.extraModulePackages merges them; ship only the modules
      # and their signing certs.
      postInstall = ''
        rm -f $out/lib/modules/${kernel.modDirVersion}/modules.*
      '';
    }) { };
in
{
  options.hardware.aic8800d80 = {
    enable = lib.mkEnableOption "AIC8800D80 USB Wi-Fi 6 adapter driver";
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ aic8800-kmodule ];
    boot.kernelModules = [ "aic_load_fw" "aic8800_fdrv" ];
    hardware.firmware = [ aic8800-firmware ];
    # Both the loader and aic8800_fdrv take their firmware base from this
    # param when set (loader: flat dir + filename, fdrv: get_fw_path()).
    # Point it straight at the AIC8800D80 firmware directory. For a
    # different AIC8800 variant, change the directory (or drop the line and
    # rely on the patched default path, which resolves the subdir by chip).
    boot.extraModprobeConfig = ''
      options aic_load_fw aic_fw_path=/run/current-system/firmware/aic8800D80
    '';
    services.udev.extraRules = ''
      # AIC8800 dongles enumerate as a write-protected "driver CD" USB mass
      # storage device first; ejecting that LUN makes the chip re-enumerate
      # in WLAN mode (a69c:8d80 "AIC Wlan").
      KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5721", RUN+="${pkgs.eject}/bin/eject /dev/%k"
    '';
  };
}
