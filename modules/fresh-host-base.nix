# Bootstrap-specific tweaks for freshly provisioned {a,b,c}.zxc.sx hosts.
{ ... }:
{
  # Workaround for https://github.com/NixOS/nix/issues/8502
  services.logrotate.checkConfig = false;

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.domain = "";

  system.stateVersion = "23.11";
}
