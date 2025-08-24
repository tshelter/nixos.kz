{ pkgs, config, ... }:
{
  networking.nat.enable = true;
  networking.nat.externalInterface = "ens3";
  networking.nat.internalInterfaces = [ "wg0" ];
  boot.kernel.sysctl."net.ipv4.ip_forward" = "1";
  networking.firewall.allowedUDPPorts = [ 45767 ];

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg0 = {
    ips = [ "192.168.99.1/24" ];
    listenPort = 45767;
    privateKeyFile = config.age.secrets.wireguard.path;
    peers = [
      {
        name = "dev@zxc.sx_m14";
        publicKey = "ecBKpuegpCBHF3MmcNEaWH6HTB0AsKSchQrYVBabs18=";
        allowedIPs = [ "192.168.99.10/32" ];
      }
      {
        name = "dev@zxc.sx_taoyao";
        publicKey = "iHtL4Ykxc5rG9BGz20/VUhcYM+RuJWFoD29kl+aeL2U=";
        allowedIPs = [ "192.168.99.11/32" ];
      }
    ];
  };
}
