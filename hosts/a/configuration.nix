{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/nixos-revision.nix
    ../../modules/nix.nix
    ../../modules/fresh-host-base.nix
    ../../modules/systempkgs.nix
    ../../modules/nginx-base.nix
    ./nginx.nix
    ./secret
    ../../modules/xray.nix
    ./wireguard.nix
    ../../modules/zapret.nix
    ./telegram-bot-api.nix
    ./yetdlp.nix
  ];

  networking.hostName = "a";
}
