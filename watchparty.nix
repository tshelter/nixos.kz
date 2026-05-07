{ pkgs, ... }:
let
  watchpartyRev = "dc3adba0edd30170340da61f74623914d61cc6bd";
  watchpartyDomain = "wp.zxc.sx";
  watchpartyRoot = "/var/lib/watchparty";
  watchpartyRelease = "${watchpartyRoot}/releases/${watchpartyRev}";
  watchpartyCurrent = "${watchpartyRoot}/current";
  watchpartyEnv = ''
    HOST=127.0.0.1
    PORT=8081
    VITE_SERVER_HOST=https://${watchpartyDomain}
    VITE_FIREBASE_CONFIG=
    ROOM_CAPACITY=0
    ROOM_CAPACITY_SUB=0
    VBROWSER_SESSION_SECONDS=86400
    VBROWSER_SESSION_SECONDS_LARGE=86400
    VM_MANAGER_CONFIG=Docker:standard:US:0:0:${watchpartyDomain},Docker:large:US:0:0:${watchpartyDomain}
  '';
  certDir = "/etc/letsencrypt/live/${watchpartyDomain}";
in
{
  networking.hosts."127.0.0.1" = [ watchpartyDomain ];
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 5000;
      to = 5063;
    }
  ];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 59000;
      to = 65399;
    }
  ];

  security.acme.certs."${watchpartyDomain}".reloadServices = [
    "nginx.service"
    "watchparty-cert-sync.service"
  ];

  system.activationScripts.watchpartyLocalSsh = ''
    install -d -m 700 /root/.ssh
    if [ ! -f /root/.ssh/id_rsa ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
    fi
    key_entry="from=\"127.0.0.1,::1\" $(cat /root/.ssh/id_rsa.pub)"
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    grep -qxF "$key_entry" /root/.ssh/authorized_keys || echo "$key_entry" >> /root/.ssh/authorized_keys
  '';

  systemd.services."watchparty-cert-sync" = {
    description = "Sync ACME certificate for WatchParty Chromium containers";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      if [ ! -f /var/lib/acme/${watchpartyDomain}/fullchain.pem ] || [ ! -f /var/lib/acme/${watchpartyDomain}/key.pem ]; then
        exit 0
      fi

      install -d -m 755 ${certDir}
      install -m 644 /var/lib/acme/${watchpartyDomain}/fullchain.pem ${certDir}/fullchain.pem
      install -m 600 /var/lib/acme/${watchpartyDomain}/key.pem ${certDir}/privkey.pem
    '';
  };

  systemd.services."watchparty-prepare" = {
    description = "Prepare WatchParty release";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      gcc
      gnumake
      curl
      gnutar
      gzip
      nodejs
      pkg-config
      python3
      coreutils
      findutils
    ];
    script = ''
      set -euo pipefail

      install -d -m 755 ${watchpartyRoot}/releases

      if [ ! -d ${watchpartyRelease} ]; then
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT

        curl -fsSL https://github.com/howardchung/watchparty/archive/${watchpartyRev}.tar.gz \
          | tar -xzf - -C "$tmpdir"

        src="$tmpdir/watchparty-${watchpartyRev}"

        cat > "$src/.env" <<'EOF'
${watchpartyEnv}
EOF

        cd "$src"
        npm ci
        npm run build

        mv "$src" ${watchpartyRelease}
      fi

      ln -sfn ${watchpartyRelease} ${watchpartyCurrent}
    '';
  };

  systemd.services.watchparty = {
    description = "WatchParty web application";
    after = [ "network-online.target" "watchparty-prepare.service" ];
    wants = [ "network-online.target" "watchparty-prepare.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nodejs ];
    serviceConfig = {
      WorkingDirectory = watchpartyCurrent;
      ExecStart = "${pkgs.nodejs}/bin/node server/server.ts";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services."watchparty-vmworker" = {
    description = "WatchParty local Chromium VM worker";
    after = [
      "network-online.target"
      "docker.service"
      "watchparty-cert-sync.service"
      "watchparty-prepare.service"
    ];
    wants = [
      "network-online.target"
      "docker.service"
      "watchparty-cert-sync.service"
      "watchparty-prepare.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nodejs ];
    environment = {
      NODE_ENV = "development";
      SSL_CRT_FILE = "${certDir}/fullchain.pem";
      SSL_KEY_FILE = "${certDir}/privkey.pem";
    };
    serviceConfig = {
      WorkingDirectory = watchpartyCurrent;
      ExecStart = "${pkgs.nodejs}/bin/node server/vmWorker.ts";
      Restart = "always";
      RestartSec = 5;
    };
  };

  virtualisation.docker.enable = true;
}
