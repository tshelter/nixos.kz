{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self
    , nixpkgs
    , disko
    , agenix
    , ...
    }@attrs:
    {
      nixosConfigurations.gtw = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        specialArgs = attrs // { inherit system; };
        modules = [
          disko.nixosModules.disko
          agenix.nixosModules.default
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
