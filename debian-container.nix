{ pkgs, ... }:
{
  system.activationScripts.debianBootstrap = {
    text = ''
      mkdir -p /var/lib/machines
      if [ ! -d /var/lib/machines/debian ]; then
        echo "Bootstrapping Debian bookworm..."
        ${pkgs.debootstrap}/bin/debootstrap \
          --include=openssh-server \
          bookworm \
          /var/lib/machines/debian

        cat > /var/lib/machines/debian/etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto host0
iface host0 inet static
  address 10.4.26.2
  netmask 255.255.255.0
  gateway 10.4.26.1
EOF

        printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" \
          > /var/lib/machines/debian/etc/resolv.conf

        systemctl --root=/var/lib/machines/debian enable ssh
      fi
    '';
    deps = [ ];
  };

  systemd.nspawn.debian = {
    execConfig.Boot = true;
    networkConfig.Bridge = "br-debian";
  };

  systemd.services."systemd-nspawn@debian".wantedBy = [ "machines.target" ];

  networking.bridges."br-debian".interfaces = [ ];
  networking.interfaces."br-debian".ipv4.addresses = [
    { address = "10.4.26.1"; prefixLength = 24; }
  ];

  networking.nat = {
    enable = true;
    internalInterfaces = [ "br-debian" ];
    externalInterface = "enp1s0";
    forwardPorts = [
      {
        proto = "tcp";
        sourcePort = 2222;
        destination = "10.4.26.2:22";
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 2222 ];
}
