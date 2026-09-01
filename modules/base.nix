{ pkgs, ... }:
{
  services.fail2ban.enable = true;

  services.openssh.enable = true;
  # Hosts are under a constant SSH brute-force flood; we only ever log in with
  # keys. Turning off password / keyboard-interactive auth stops each bogus
  # connection from spawning a PAM session attempt.
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;

  # An earlier deploy swapped the D-Bus implementation without restarting
  # systemd-logind, leaving logind bound to a dead bus: every SSH login then
  # blocked in pam_systemd for ~25-120s and `switch-to-configuration` failed
  # ("Unable to list users with logind"). Pin the implementation, and make a
  # change to the bus config force a logind restart in the same activation.
  services.dbus.implementation = "broker";
  systemd.services.systemd-logind.restartTriggers = [ pkgs.dbus-broker ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjfs0cclnYa2sURF6v0qyLWLeVHI1HjdP7aBUsmZapO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs3wni2hqJbKAPyzRawZHAO2jNWDxZ4Zkw8XFwiKZeA"
  ];
}
