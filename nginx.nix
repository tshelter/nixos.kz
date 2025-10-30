{ pkgs, ... }:
{
  services.nginx = {
    enable = true;
    package = pkgs.nginxQuic;

    virtualHosts."ip.zxc.sx" = {
      quic = true;
      addSSL = true;
      enableACME = true;
      extraConfig = "default_type text/plain;";
      locations."/" = {
        return = "200 \"$remote_addr\n\"";
      };
    };

    virtualHosts."nixos.kz" = {
      quic = true;
      addSSL = true;
      enableACME = true;
      serverAliases = [ "www.nixos.kz" ];
      locations."/" = {
        return = "301 https://t.me/NixOSkz";
      };
    };

    virtualHosts."cache.nixos.kz" = {
      quic = true;
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "https://cache.nixos.org";
        extraConfig = ''
          proxy_set_header Host cache.nixos.org;
          proxy_ssl_server_name on;
          proxy_redirect off;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "webmaster@nixos.kz";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];
}
