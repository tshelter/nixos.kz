{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "minecraft-server"
  ];

  services.minecraft-server = {
    enable = true;
    eula = true;
    openFirewall = true;
    declarative = true;
    whitelist = {
      # curl -s https://api.mojang.com/users/profiles/minecraft/dynzas | jq -r '.id | "\(.[0:8])-\(.[8:12])-\(.[12:16])-\(.[16:20])-\(.[20:])"'
      dynzas = "69742bb1-d556-449e-bfcc-20fbf644e8db";
      hand7s = "87adcacf-668b-4d17-a318-970c5b437d9a";
      venix756 = "498d50dc-f90a-4889-ac4c-878b20e98a17";
    };
    package = pkgs.minecraftServers.vanilla-1-20;
    serverProperties = {
      motd = "NixOS.kz Minecraft server!";
      white-list = true;
      online-mode = true;
    };
    jvmOpts = "-Xms4096M -Xmx4096M";
  };
}
