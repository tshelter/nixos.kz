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
      dynzas = "69742bb1-d556-449e-bfcc-20fbf644e8db";
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
