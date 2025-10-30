{ pkgs, config, ... }:
{
  networking.firewall.allowedTCPPorts = [ 5222 5269 ];

  services.prosody = {
    enable = true;
    allowRegistration = false;
    xmppComplianceSuite = false;
    admins = [ "admin@zxc.sx" ];
    virtualHosts."zxc.sx" = {
      enabled = true;
      domain = "zxc.sx";
      ssl = {
        key = "/var/lib/acme/zxc.sx/key.pem";
        cert = "/var/lib/acme/zxc.sx/fullchain.pem";
      };
    };
  };

  security.acme = {
    certs."zxc.sx" = {
      email = "dev@zxc.sx";
      dnsProvider = "cloudflare";
      credentialFiles = {
        "CF_DNS_API_TOKEN_FILE" = config.age.secrets.cloudflare.path;
      };
      extraDomainNames = [ "xmpp.zxc.sx" ];
      postRun = ''
        ${pkgs.acl}/bin/setfacl \
          -Rm u:prosody:rx \
          /var/lib/acme/zxc.sx
      '';
      reloadServices = [ "prosody.service" ];
    };
  };
  environment.systemPackages = with pkgs; [ acl ];
}
