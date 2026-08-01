{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.deploy-rs.url = "github:serokell/deploy-rs";
  inputs.deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self
    , nixpkgs
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

      # One entry per server. `domain` is the SSH/deploy target.
      # `extraModules` are host modules that aren't already imported from
      # within hosts/<name>/configuration.nix itself.
      hosts = {
        gtw = {
          domain = "nixos.kz";
          extraModules = [ ./hosts/gtw/hardware-configuration.nix ];
        };
        a = {
          domain = "a.zxc.sx";
          extraModules = [ ];
        };
        b = {
          domain = "b.zxc.sx";
          extraModules = [ ];
        };
        # c = { domain = "c.zxc.sx"; extraModules = [ ]; };
      };

      mkHost = name: { extraModules, ... }: nixpkgs.lib.nixosSystem rec {
        inherit system;
        specialArgs = attrs // { inherit system; };
        modules = [
          agenix.nixosModules.default
          ./hosts/${name}/configuration.nix
        ] ++ extraModules;
      };

      mkDeployNode = name: { domain, ... }: {
        hostname = domain;
        profiles.system = {
          user = "root";
          sshUser = "root";
          remoteBuild = true;
          fastConnection = true;
          path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
        };
      };
    in
    {
      nixosConfigurations = builtins.mapAttrs mkHost hosts;
      deploy.nodes = builtins.mapAttrs mkDeployNode hosts;
      #      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
