# yetdlp — Telegram bot (@yetdlpbot) that downloads TikTok / Instagram
# videos and photos without ads. Source lives in ./yetdlp/bot.py.
#
# The bot token (and any other config) comes from an agenix env-file secret
# ./secret/yetdlp.age, which must contain shell-style KEY=VALUE lines, e.g.:
#
#     BOT_TOKEN=123456:ABC...
#     ALLOWED_USER_IDS=111 222      # optional; empty = anyone may use it
#
# Instagram photo posts / carousels (yt-dlp can't fetch those anonymously)
# fall back to sssinstagram.com, driven through a headless Chromium
# (./yetdlp/sssig.py) since its API request is signed by obfuscated JS.
{ pkgs, config, ... }:

let
  pyEnv = pkgs.python3.withPackages (ps: [
    ps.aiogram
    ps.yt-dlp
    ps.playwright
  ]);
in
{
  systemd.services.yetdlp = {
    description = "yetdlp Telegram media-download bot";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = [ pkgs.ffmpeg ];

    environment = {
      STATE_DIR = "/var/lib/yetdlp";
      PYTHONUNBUFFERED = "1";
      HOME = "/var/lib/yetdlp";
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
    };

    serviceConfig = {
      ExecStart = "${pyEnv}/bin/python ${./yetdlp}/bot.py";
      EnvironmentFile = config.age.secrets.yetdlp.path;
      DynamicUser = true;
      StateDirectory = "yetdlp";
      WorkingDirectory = "/var/lib/yetdlp";
      Restart = "on-failure";
      RestartSec = 10;

      # a.zxc.sx is a 1GB box; Chromium (only spun up for Instagram photo
      # posts, reaped after 15min idle) is the biggest consumer here — cap it
      # so a runaway page can't take the rest of the system down with it.
      MemoryHigh = "650M";
      MemoryMax = "800M";

      # hardening (MemoryDenyWriteExecute stays off: Chromium's JIT needs W+X)
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
