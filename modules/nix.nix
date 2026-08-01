{ self, lib, ... }:
{
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nix.registry.nixpkgs.flake = self.inputs.nixpkgs;
  nix.registry.n.flake = self.inputs.nixpkgs;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "04:00" ];

  nix.settings.substituters = lib.mkForce [
    #   "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store/"
    "https://nixos-cache-proxy.cofob.dev"
    "https://mirror.yandex.ru/nixos/"
    "https://cache.nixos.kz"
    "https://cache.nixos.org"
  ];
}
