{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/nix.nix
    ../../modules/fresh-host-base.nix
    ../../modules/systempkgs.nix
    ../../modules/nginx-base.nix
    ./nginx.nix
    ./secret
    ../../modules/xray.nix
  ];

  networking.hostName = "a";
}
