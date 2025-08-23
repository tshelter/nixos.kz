{ self, ... }:
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
}
