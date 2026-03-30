{ pkgs, config, ... }:
{
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp1s0";
  networking.nat.internalInterfaces = [ "wg0" ];
  boot.kernel.sysctl."net.ipv4.ip_forward" = "1";
  networking.firewall.allowedUDPPorts = [ 443 ];

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg0 = {
    ips = [ "192.168.99.1/24" ];
    listenPort = 443;
    # PublicKey = "YuJumLl5T8trwIjeseCWEgg55V10ECQP2atUnD50uzM=";
    privateKeyFile = config.age.secrets.wireguard.path;
    peers = [
      {
        name = "dev@zxc.sx_m14";
        publicKey = "ecBKpuegpCBHF3MmcNEaWH6HTB0AsKSchQrYVBabs18=";
        allowedIPs = [ "192.168.99.10/32" ];
      }
      {
        name = "dev@zxc.sx_taoyao";
        publicKey = "BYqXjD930Yi4WAhdH+7r9NTIk/yJW3fYasxgQm/zYC8=";
        allowedIPs = [ "192.168.99.11/32" ];
      }
      {
        name = "dev@zxc.sx_t14s";
        publicKey = "B+pzwl4qX7XLaNhuA+ZbuZ/0VbjupgVd2Q45v7mAPTQ=";
        allowedIPs = [ "192.168.99.12/32" ];
      }
    ];
  };
}
