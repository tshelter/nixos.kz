{ self, system, lib, ... }:
{
  environment.systemPackages = [
    self.inputs.agenix.packages."${system}".default
  ];
  age.secrets = lib.mapAttrs'
    (n: v: {
      name = builtins.replaceStrings [ ".age" ] [ "" ] n;
      value = { file = ./${n}; };
    })
    (import ./secrets.nix);
}
