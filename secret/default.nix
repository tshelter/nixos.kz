{ self, system, ... }:
{
  environment.systemPackages = [
    self.inputs.agenix.packages."${system}".default
  ];
  age.secrets.xray.file = ./xray.age;
  age.secrets.wireguard.file = ./wireguard.age;
}
