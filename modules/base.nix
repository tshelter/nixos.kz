{ pkgs, ... }:
{
  services.fail2ban.enable = true;

  services.openssh.enable = true;
  # Hosts are under a constant SSH brute-force flood; we only ever log in with
  # keys. Turning off password / keyboard-interactive auth stops each bogus
  # connection from spawning a PAM session attempt.
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;

  # dbus-broker can restart independently of any nix-triggered change (crash,
  # resource pressure during a concurrent deploy, etc). logind does not
  # reconnect to a fresh bus instance on its own, so once orphaned every
  # pam_systemd call hangs forever: SSH logins block for minutes and
  # `switch-to-configuration` itself wedges at 100% CPU ("Unable to list
  # users with logind"), since it needs logind too. A restartTrigger keyed to
  # the dbus-broker package only covers the case where OUR config changes
  # dbus-broker; it does nothing for a runtime restart between deploys. Tie
  # logind's lifecycle to dbus-broker's directly so systemd force-restarts it
  # the moment dbus-broker restarts, for any reason, without waiting on the
  # next activation.
  services.dbus.implementation = "broker";
  systemd.services.systemd-logind = {
    bindsTo = [ "dbus-broker.service" ];
    after = [ "dbus-broker.service" ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjfs0cclnYa2sURF6v0qyLWLeVHI1HjdP7aBUsmZapO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs3wni2hqJbKAPyzRawZHAO2jNWDxZ4Zkw8XFwiKZeA"
  ];
}
