{ config, pkgs, ... }:
let
  port = 50740;
  configTemplate = pkgs.writeText "mtproto-config.py.tmpl" ''
    PORT = ${toString port}
    USERS = {"tg": "@SECRET@"}
    SECURE_ONLY = True
  '';
in
{
  systemd.services.mtprotoproxy = {
    description = "MTProto Proxy Daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      LoadCredential = "secret:${config.age.secrets.mtproto.path}";
      DynamicUser = true;
      RuntimeDirectory = "mtprotoproxy";
    };
    script = ''
      secret=$(cat "$CREDENTIALS_DIRECTORY/secret")
      sed "s/@SECRET@/$secret/" ${configTemplate} > "$RUNTIME_DIRECTORY/config.py"
      exec ${pkgs.mtprotoproxy}/bin/mtprotoproxy "$RUNTIME_DIRECTORY/config.py"
    '';
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
