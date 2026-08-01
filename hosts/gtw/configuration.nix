{ modulesPath
, lib
, pkgs
, ...
} @ args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/base.nix
    ./secret
    ../../modules/nginx.nix
    ../../modules/xray.nix
    ../../modules/nix.nix
    ./network.nix
    ../../modules/wireguard.nix
    ../../modules/systempkgs.nix
    ../../modules/dpdk.nix
    ../../modules/zapret.nix
    ../../modules/minecraft.nix
    ../../modules/jellyfin.nix
    ../../modules/debian-container.nix
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "24.05";
}
