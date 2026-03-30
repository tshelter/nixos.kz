{ modulesPath
, lib
, pkgs
, ...
} @ args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./secret
#    ./nginx.nix
    ./xray.nix
    ./nix.nix
    ./wireguard.nix
    ./systempkgs.nix
    ./zapret.nix
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.fail2ban.enable = true;
  services.openssh.enable = true;

  networking.hostName = "gtw";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "185.215.163.166";
      prefixLength = 29;
    }
  ];
  networking.defaultGateway = "185.215.163.161";
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjfs0cclnYa2sURF6v0qyLWLeVHI1HjdP7aBUsmZapO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs3wni2hqJbKAPyzRawZHAO2jNWDxZ4Zkw8XFwiKZeA"
  ];

  system.stateVersion = "24.05";
}
