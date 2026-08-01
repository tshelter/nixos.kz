# Shared nginx/ACME baseline for hosts that only need a simple vhost
# (unlike gtw's modules/nginx.nix, which carries its own full vhost set).
{ ... }:
{
  services.nginx.enable = true;

  security.acme = {
    acceptTerms = true;
    defaults.email = "webmaster@nixos.kz";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
