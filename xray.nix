{ config, lib, ... }:
{
  services.xray = {
    enable = true;
    settingsFile = config.age.secrets.xray.path;
  };

  # Default module doesn't allow using YAML instead of JSON for config
  systemd.services.xray = {
    serviceConfig.LoadCredential = lib.mkForce "config.yaml:${config.services.xray.settingsFile}";
    script = lib.mkForce ''
      exec "${config.services.xray.package}/bin/xray" -config "$CREDENTIALS_DIRECTORY/config.yaml"
    '';
  };

  networking.firewall.allowedTCPPorts = [ 61443 61444 62443 ];
}
