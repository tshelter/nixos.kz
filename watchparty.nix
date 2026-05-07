{ pkgs, ... }:
let
  watchpartyRevision = "dc3adba0edd30170340da61f74623914d61cc6bd";
  watchpartyImage = "watchparty:${watchpartyRevision}";
  watchpartySource = pkgs.fetchzip {
    url = "https://github.com/howardchung/watchparty/archive/${watchpartyRevision}.tar.gz";
    hash = "sha256-NU70RiRkeD0QffLZef2Xuy4yaAYVHhd+mY+K+0xwyXM=";
  };
  watchpartyDbUrl = "postgresql://watchparty@127.0.0.1:5432/watchparty?sslmode=disable";
  watchpartyHost = "wp.zxc.sx";
  watchpartyPort = 18080;
  watchpartyVmworkerPort = 13100;
in
{
  users.groups.watchparty = { };
  users.users.watchparty = {
    isSystemUser = true;
    group = "watchparty";
    home = "/var/lib/watchparty";
    createHome = true;
    extraGroups = [ "docker" ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keyFiles = [ "/var/lib/watchparty/.ssh/id_rsa.pub" ];
  };

  virtualisation.docker.enable = true;

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    settings.listen_addresses = "127.0.0.1";
    authentication = ''
      local all all peer
      host watchparty watchparty 127.0.0.1/32 trust
      host watchparty watchparty ::1/128 trust
    '';
    ensureDatabases = [ "watchparty" ];
    ensureUsers = [
      {
        name = "watchparty";
        ensureDBOwnership = true;
      }
    ];
    initialScript = pkgs.writeText "watchparty-schema.sql" ''
      \connect watchparty
      \i ${watchpartySource}/sql/schema.sql
    '';
  };

  systemd.services.watchparty-bootstrap = {
    description = "Bootstrap local WatchParty secrets";
    wantedBy = [ "multi-user.target" ];
    before = [
      "watchparty-image.service"
      "watchparty.service"
      "watchparty-vmworker.service"
    ];
    path = with pkgs; [
      coreutils
      openssh
      openssl
      util-linux
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      install -d -m 0700 -o watchparty -g watchparty /var/lib/watchparty/.ssh

      if [ ! -f /var/lib/watchparty/.ssh/id_rsa ]; then
        runuser -u watchparty -- \
          ssh-keygen -q -t rsa -b 4096 -N "" -f /var/lib/watchparty/.ssh/id_rsa
      fi

      if [ ! -f /var/lib/watchparty/vbrowser-admin-key ]; then
        umask 0077
        openssl rand -hex 32 > /var/lib/watchparty/vbrowser-admin-key
        chown watchparty:watchparty /var/lib/watchparty/vbrowser-admin-key
      fi

      if [ ! -e /etc/letsencrypt ]; then
        ln -s /var/lib/acme /etc/letsencrypt
      fi
    '';
  };

  systemd.services.watchparty-image = {
    description = "Build the local WatchParty image";
    requires = [
      "docker.service"
      "watchparty-bootstrap.service"
    ];
    after = [
      "docker.service"
      "watchparty-bootstrap.service"
    ];
    path = with pkgs; [
      coreutils
      docker
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      if docker image inspect ${watchpartyImage} >/dev/null 2>&1; then
        exit 0
      fi

      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT
      cp -R ${watchpartySource}/. "$tmpdir"
      chmod -R u+w "$tmpdir"

      printf '%s\n' \
        VITE_SERVER_HOST=https://${watchpartyHost} \
        VITE_OAUTH_REDIRECT_HOSTNAME=https://${watchpartyHost} \
        VITE_FIREBASE_CONFIG= \
        > "$tmpdir/.env"

      docker build -t ${watchpartyImage} "$tmpdir"
    '';
  };

  systemd.services.watchparty = {
    description = "Run WatchParty";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-image.service"
    ];
    after = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-image.service"
    ];
    path = [ pkgs.docker ];
    preStart = ''
      docker rm -f watchparty >/dev/null 2>&1 || true
    '';
    script = ''
      set -euo pipefail

      exec docker run --rm --name watchparty --network host \
        -e DATABASE_URL=${watchpartyDbUrl} \
        -e PORT=${toString watchpartyPort} \
        -e HOST=127.0.0.1 \
        -e ROOM_CAPACITY=0 \
        -e ROOM_CAPACITY_SUB=0 \
        -e VMWORKER_PORT=${toString watchpartyVmworkerPort} \
        ${watchpartyImage}
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.watchparty-vmworker = {
    description = "Run WatchParty vmWorker";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-image.service"
    ];
    after = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-image.service"
    ];
    path = [ pkgs.docker ];
    preStart = ''
      docker rm -f watchparty-vmworker >/dev/null 2>&1 || true
    '';
    script = ''
      set -euo pipefail

      exec docker run --rm --name watchparty-vmworker --network host \
        -v /var/lib/watchparty/.ssh:/root/.ssh:ro \
        -v /etc/letsencrypt:/etc/letsencrypt:ro \
        -e DATABASE_URL=${watchpartyDbUrl} \
        -e NODE_ENV=development \
        -e DOCKER_VM_HOST_SSH_USER=watchparty \
        -e VBROWSER_ADMIN_KEY="$(cat /var/lib/watchparty/vbrowser-admin-key)" \
        -e VBROWSER_SESSION_SECONDS=31536000 \
        -e VBROWSER_SESSION_SECONDS_LARGE=31536000 \
        -e VM_MANAGER_CONFIG=Docker:standard:EU:0:64:${watchpartyHost} \
        -e VMWORKER_PORT=${toString watchpartyVmworkerPort} \
        -e SSL_KEY_FILE=/etc/letsencrypt/${watchpartyHost}/key.pem \
        -e SSL_CRT_FILE=/etc/letsencrypt/${watchpartyHost}/fullchain.pem \
        ${watchpartyImage} \
        node server/vmWorker.ts
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };
  };

  services.nginx.virtualHosts.${watchpartyHost} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString watchpartyPort}";
      proxyWebsockets = true;
    };
  };

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
}
