{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.deploy-rs.url = "github:serokell/deploy-rs";
  inputs.deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self
    , nixpkgs
    , disko
    , agenix
    , deploy-rs
    , ...
    }@attrs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      deployPkgs = import nixpkgs {
        inherit system;
        overlays = [
          deploy-rs.overlays.default
          (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
        ];
      };
    in
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
      deploy.nodes.gtw =
        {
          hostname = "nixos.kz";
          profiles.system = {
            user = "root";
            sshUser = "root";
            remoteBuild = true;
            fastConnection = true;
            path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.gtw;
          };
        };
      #      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
