{ ... }:
{
  services.fail2ban.enable = true;
  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjfs0cclnYa2sURF6v0qyLWLeVHI1HjdP7aBUsmZapO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs3wni2hqJbKAPyzRawZHAO2jNWDxZ4Zkw8XFwiKZeA"
  ];
}
