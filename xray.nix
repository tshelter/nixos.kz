{ ... }:
{
  services.xray = {
    enable = true;
    settingsFile = "/var/lib/secret/xray.json";
  };
  networking.firewall.allowedTCPPorts = [ 61443 ];
}
