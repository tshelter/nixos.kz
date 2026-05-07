{ pkgs, ... }:
let
  # Pinned upstream WatchParty revision for the local deployment on wp.zxc.sx.
  watchpartyRevision = "dc3adba0edd30170340da61f74623914d61cc6bd";
  watchpartyImage = "watchparty:${watchpartyRevision}-nixos1";
  watchpartyServerContainerName = "watchparty";
  watchpartyVmworkerContainerName = "watchparty-vmworker";
  watchpartySource = pkgs.fetchzip {
    url = "https://github.com/howardchung/watchparty/archive/${watchpartyRevision}.tar.gz";
    hash = "sha256-NU70RiRkeD0QffLZef2Xuy4yaAYVHhd+mY+K+0xwyXM=";
  };
  watchpartyDockerTlsPatch = pkgs.writeText "watchparty-docker-tls.patch" ''
    diff --git a/server/vm/docker.ts b/server/vm/docker.ts
    --- a/server/vm/docker.ts
    +++ b/server/vm/docker.ts
    @@ -31,8 +31,7 @@ export class Docker extends VMManager {
         const sslEnv =
    -      config.NODE_ENV === "development" &&
    -      config.SSL_KEY_FILE &&
    +      config.SSL_KEY_FILE &&
           config.SSL_CRT_FILE
             ? `-e NEKO_KEY="${config.SSL_KEY_FILE}" -e NEKO_CERT="${config.SSL_CRT_FILE}"`
             : "";
    @@ -43,7 +42,7 @@ export class Docker extends VMManager {
           PORT=$(comm -23 <(seq 5000 5063 | sort) <(ss -Htan | awk '{print $4}' | cut -d':' -f2 | sort -u) | sort -n | head -n 1)
           INDEX=$(($PORT - 5000))
           UDP_START=$((59000+$INDEX*100))
           UDP_END=$((59099+$INDEX*100))
    -      docker run -d --rm --name=${name} --memory="2g" --cpus="2" -p $PORT:$PORT -p $UDP_START-$UDP_END:$UDP_START-$UDP_END/udp -v /etc/letsencrypt:/etc/letsencrypt -l ${tag} -l index=$INDEX --log-opt max-size=1g --shm-size=1g --cap-add="SYS_ADMIN" ${sslEnv} -e DISPLAY=":99.0" -e NEKO_PASSWORD=${name} -e NEKO_PASSWORD_ADMIN=${name} -e NEKO_ADMIN_KEY=${config.VBROWSER_ADMIN_KEY} -e NEKO_BIND=":$PORT" -e NEKO_EPR=":$UDP_START-$UDP_END" -e NEKO_H264="1" ${imageName}
    +      docker run -d --rm --name=${name} --memory="2g" --cpus="2" -p $PORT:$PORT -p $UDP_START-$UDP_END:$UDP_START-$UDP_END/udp -v /var/lib/acme:/var/lib/acme -l ${tag} -l index=$INDEX --log-opt max-size=1g --shm-size=1g --cap-add="SYS_ADMIN" ${sslEnv} -e DISPLAY=":99.0" -e NEKO_PASSWORD=${name} -e NEKO_PASSWORD_ADMIN=${name} -e NEKO_ADMIN_KEY=${config.VBROWSER_ADMIN_KEY} -e NEKO_BIND=":$PORT" -e NEKO_EPR=":$UDP_START-$UDP_END" -e NEKO_H264="1" ${imageName}
  '';
  watchpartyHost = "wp.zxc.sx";
  watchpartyPort = 18080;
  watchpartyVmworkerPort = 13100;
  watchpartyDbPasswordFile = "/var/lib/watchparty/db-password";
  noRoomCapacityLimit = 0;
  oneYearInSeconds = 365 * 24 * 60 * 60;
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
  };

  virtualisation.docker.enable = true;

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    settings.listen_addresses = "127.0.0.1";
    authentication = ''
      local all all peer
      host watchparty watchparty 127.0.0.1/32 scram-sha-256
      host watchparty watchparty ::1/128 scram-sha-256
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      install -d -m 0700 -o watchparty -g watchparty /var/lib/watchparty/.ssh

      if [ ! -f /var/lib/watchparty/.ssh/id_rsa ]; then
        runuser -u watchparty -- \
          ssh-keygen -q -t rsa -b 4096 -N "" -f /var/lib/watchparty/.ssh/id_rsa
      fi
      # vmWorker connects back to the local Docker host over SSH, so authorize the generated key for the same user.
      cat /var/lib/watchparty/.ssh/id_rsa.pub > /var/lib/watchparty/.ssh/authorized_keys
      chown watchparty:watchparty /var/lib/watchparty/.ssh/authorized_keys
      chmod 0600 /var/lib/watchparty/.ssh/authorized_keys

      if [ ! -f /var/lib/watchparty/vbrowser-admin-key ]; then
        umask 0077
        openssl rand -hex 32 > /var/lib/watchparty/vbrowser-admin-key
        chown watchparty:watchparty /var/lib/watchparty/vbrowser-admin-key
      fi

      if [ ! -f /var/lib/watchparty/db-password ]; then
        umask 0077
        openssl rand -hex 32 > /var/lib/watchparty/db-password
        chown watchparty:watchparty /var/lib/watchparty/db-password
      fi

    '';
  };

  systemd.services.watchparty-postgresql-setup = {
    description = "Prepare local WatchParty PostgreSQL state";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "postgresql.service"
      "watchparty-bootstrap.service"
    ];
    after = [
      "postgresql.service"
      "watchparty-bootstrap.service"
    ];
    before = [
      "watchparty.service"
      "watchparty-vmworker.service"
    ];
    path = [
      pkgs.coreutils
      pkgs.postgresql
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      set -euo pipefail

      password="$(tr -d '\n' < ${watchpartyDbPasswordFile})"

      if [ "$(psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'watchparty'")" != '1' ]; then
        printf '%s\n' \
          "\set watchparty_password $password" \
          "CREATE ROLE watchparty LOGIN PASSWORD :'watchparty_password'" \
          | psql -v ON_ERROR_STOP=1 -d postgres
      else
        printf '%s\n' \
          "\set watchparty_password $password" \
          "ALTER ROLE watchparty WITH PASSWORD :'watchparty_password'" \
          | psql -v ON_ERROR_STOP=1 -d postgres
      fi

      if [ "$(psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'watchparty'")" != '1' ]; then
        psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE watchparty OWNER watchparty"
      fi

      if [ "$(psql -d watchparty -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'room'")" != '1' ]; then
        psql -v ON_ERROR_STOP=1 -d watchparty -f ${watchpartySource}/sql/schema.sql
      fi
    '';
  };

  systemd.services.watchparty-image = {
    description = "Build the local WatchParty image";
    wantedBy = [ "multi-user.target" ];
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
      patch
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
      patch -d "$tmpdir" -p1 < ${watchpartyDockerTlsPatch}

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
      "watchparty-postgresql-setup.service"
      "watchparty-image.service"
    ];
    after = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-postgresql-setup.service"
      "watchparty-image.service"
    ];
    path = [ pkgs.docker ];
    preStart = ''
      docker rm -f ${watchpartyServerContainerName} >/dev/null 2>&1 || true
    '';
    script = ''
      set -euo pipefail

      dbPassword="$(cat ${watchpartyDbPasswordFile})"
      exec docker run --rm --name ${watchpartyServerContainerName} --network host \
        -e DATABASE_URL="postgresql://watchparty:$dbPassword@127.0.0.1:5432/watchparty?sslmode=disable" \
        -e PORT=${toString watchpartyPort} \
        -e HOST=127.0.0.1 \
        -e ROOM_CAPACITY=${toString noRoomCapacityLimit} \
        -e ROOM_CAPACITY_SUB=${toString noRoomCapacityLimit} \
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
      "watchparty-postgresql-setup.service"
      "watchparty-image.service"
    ];
    after = [
      "docker.service"
      "postgresql.service"
      "watchparty-bootstrap.service"
      "watchparty-postgresql-setup.service"
      "watchparty-image.service"
    ];
    path = [ pkgs.docker ];
    preStart = ''
      docker rm -f ${watchpartyVmworkerContainerName} >/dev/null 2>&1 || true
    '';
    script = ''
      set -euo pipefail

      dbPassword="$(cat ${watchpartyDbPasswordFile})"
      # Docker:standard:EU:0:64:${watchpartyHost} = provider:tier:region:minReady:maxReady:publicHost.
      # Here minReady=0 keeps no browsers permanently warm, while maxReady=64 allows up to 64 local Chromium sessions.
      exec docker run --rm --name ${watchpartyVmworkerContainerName} --network host \
        -v /var/lib/watchparty/.ssh:/root/.ssh:ro \
        -v /var/lib/acme:/var/lib/acme:ro \
        -e DATABASE_URL="postgresql://watchparty:$dbPassword@127.0.0.1:5432/watchparty?sslmode=disable" \
        -e NODE_ENV=production \
        -e DOCKER_VM_HOST_SSH_USER=watchparty \
        -e VBROWSER_ADMIN_KEY="$(cat /var/lib/watchparty/vbrowser-admin-key)" \
        -e VBROWSER_SESSION_SECONDS=${toString oneYearInSeconds} \
        -e VBROWSER_SESSION_SECONDS_LARGE=${toString oneYearInSeconds} \
        -e VM_MANAGER_CONFIG=Docker:standard:EU:0:64:${watchpartyHost} \
        -e VMWORKER_PORT=${toString watchpartyVmworkerPort} \
        -e SSL_KEY_FILE=/var/lib/acme/${watchpartyHost}/key.pem \
        -e SSL_CRT_FILE=/var/lib/acme/${watchpartyHost}/fullchain.pem \
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
