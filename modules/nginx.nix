{ pkgs, ... }:
{
  services.nginx = {
    enable = true;

    virtualHosts."ip.zxc.sx" = {
      addSSL = true;
      enableACME = true;
      extraConfig = "default_type text/plain;";
      locations."/" = {
        return = "200 \"$remote_addr\n\"";
      };
    };

    virtualHosts."nixos.kz" = {
      addSSL = true;
      enableACME = true;
      serverAliases = [ "www.nixos.kz" ];
      locations."/" = {
        return = "301 https://t.me/NixOSkz";
      };
    };

    virtualHosts."cache.nixos.kz" = {
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

    virtualHosts."media.zxc.sx" = {
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_buffering off;
          client_max_body_size 0;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "webmaster@nixos.kz";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
