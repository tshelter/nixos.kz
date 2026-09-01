# qBittorrent (headless, qbittorrent-nox) on b.zxc.sx.
#
# WebUI is bound to localhost and exposed only through nginx TLS at
#   https://b.zxc.sx/qbittorrent/
# Login: admin / <password generated at deploy time, kept out of the repo>.
# The Password_PBKDF2 below is a PBKDF2-HMAC-SHA512 hash (100k iterations)
# of that password — same idea as users.users.*.hashedPassword.
{ ... }:

let
  webuiPort = 8080;
  torrentPort = 51413;
in
{
  services.qbittorrent = {
    enable = true;
    inherit webuiPort;
    torrentingPort = torrentPort;
    openFirewall = false; # WebUI stays local; peer port opened explicitly below
    extraArgs = [ "--confirm-legal-notice" ];

    serverConfig = {
      LegalNotice.Accepted = true;

      BitTorrent.Session = {
        DefaultSavePath = "/var/lib/qBittorrent/downloads";
        Port = torrentPort;
      };

      Preferences.WebUI = {
        Username = "admin";
        Password_PBKDF2 =
          "@ByteArray(vw0uQ96SszFidEkVfldq9A==:cNtrCWpCR8z4s8zRmmDDgpusWsyyyqzYgrHYUlPa3Kp9lcwlcs6YNphgypGADH+XD+62ngzIbIHTfQHp5UTVNA==)";
        Address = "127.0.0.1";
        ReverseProxySupportEnabled = true;
        TrustedReverseProxiesList = "127.0.0.1";
        HostHeaderValidation = false;
        CSRFProtection = false;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent/downloads 0755 qbittorrent qbittorrent -"
  ];

  # Incoming BitTorrent peer connections only — not the WebUI.
  networking.firewall.allowedTCPPorts = [ torrentPort ];
  networking.firewall.allowedUDPPorts = [ torrentPort ];

  services.nginx.virtualHosts."b.zxc.sx".locations."/qbittorrent/" = {
    proxyPass = "http://127.0.0.1:${toString webuiPort}/";
    extraConfig = ''
      proxy_http_version 1.1;
      proxy_set_header Host 127.0.0.1:${toString webuiPort};
      proxy_set_header X-Forwarded-Host $http_host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header Referer "";
      proxy_set_header Origin "";
      proxy_cookie_path / "/; Secure";
      proxy_read_timeout 600s;
      client_max_body_size 100m;
    '';
  };
}
