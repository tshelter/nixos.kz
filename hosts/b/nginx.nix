{ pkgs, ... }:
{
  services.nginx.virtualHosts."b.zxc.sx" = {
    addSSL = true;
    enableACME = true;

    locations."/" = {
      root = import ../../modules/cache-landing.nix { inherit pkgs; };
      extraConfig = "index index.html;";
    };

    # Only the bare "/cache/" index (nix-serve's info page) gets its
    # self-referential URL rewritten. Everything else under /cache/ is an
    # actual cache object (nix-cache-info, narinfo, nar/*) and must be
    # passed through byte-for-byte, unfiltered.
    locations."= /cache/" = {
      proxyPass = "https://cache.nixos.org/";
      extraConfig = ''
        proxy_set_header Host cache.nixos.org;
        proxy_set_header Accept-Encoding "";
        proxy_ssl_server_name on;
        proxy_redirect off;
        sub_filter 'https://cache.nixos.org/' 'https://b.zxc.sx/cache/';
        sub_filter_once off;
        sub_filter_types text/html text/plain;
      '';
    };

    locations."= /cache" = {
      return = "301 https://b.zxc.sx/cache/";
    };

    locations."/cache/" = {
      proxyPass = "https://cache.nixos.org/";
      extraConfig = ''
        proxy_set_header Host cache.nixos.org;
        proxy_ssl_server_name on;
        proxy_redirect off;
      '';
    };
  };
}
