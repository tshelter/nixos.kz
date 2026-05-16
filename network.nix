{ ... }:
{
  networking.hostName = "gtw";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "185.215.163.166";
      prefixLength = 29;
    }
  ];
  networking.defaultGateway = "185.215.163.161";
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };
}
