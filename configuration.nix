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
    ./disk-config.nix
    ./nginx.nix
    ./xray.nix
    ./nix.nix
    ./wireguard.nix
  ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  networking.hostName = "gtw";
  networking.useDHCP = false;
  networking.interfaces.ens3.ipv4.addresses = [
    {
      address = "45.86.80.39";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "45.86.80.1";
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjfs0cclnYa2sURF6v0qyLWLeVHI1HjdP7aBUsmZapO"
  ];

  system.stateVersion = "24.05";
}
