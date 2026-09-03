# Local Telegram Bot API server (tdlib/telegram-bot-api).
#
# The public Bot API caps bot uploads at 50 MB, which is why longer reels /
# videos failed with "Request Entity Too Large". A self-hosted server raises
# that to 2000 MB. yetdlp points at it via TELEGRAM_API_BASE (see yetdlp.nix);
# the bot logs out of the cloud API once on first start to migrate.
#
# Credentials (TELEGRAM_API_ID / TELEGRAM_API_HASH, from https://my.telegram.org)
# come from the agenix secret ./secret/tgbotapi.age. Bound to localhost only;
# nothing else talks to it.
{ pkgs, config, ... }:

let
  port = 8081;
in
{
  systemd.services.telegram-bot-api = {
    description = "Local Telegram Bot API server (2 GB upload cap for yetdlp)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      # No --local: plain HTTP on loopback, 2000 MB upload cap (vs 50 MB on the
      # cloud API). --local would lift the cap entirely but changes file
      # semantics for no real benefit here — the bot only ever uploads.
      ExecStart = ''
        ${pkgs.telegram-bot-api}/bin/telegram-bot-api \
          --http-ip-address=127.0.0.1 \
          --http-port=${toString port} \
          --dir=/var/lib/telegram-bot-api
      '';
      # provides TELEGRAM_API_ID / TELEGRAM_API_HASH (picked up automatically)
      EnvironmentFile = config.age.secrets.tgbotapi.path;

      DynamicUser = true;
      StateDirectory = "telegram-bot-api";
      WorkingDirectory = "/var/lib/telegram-bot-api";
      Restart = "on-failure";
      RestartSec = 10;

      # tdlib idles small; headroom for a big upload streaming through.
      MemoryHigh = "260M";
      MemoryMax = "400M";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallFilter = [ "@system-service" ];
      SystemCallErrorNumber = "EPERM";
    };
  };
}
