# Test build configuration: the real system config + the aic8800 module.
# Used only to validate that everything builds before touching /etc/nixos.
{
  imports = [
    /etc/nixos/configuration.nix
    ./aic8800.nix
  ];

  hardware.aic8800d80.enable = true;
}
