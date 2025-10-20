let
  zxc = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx";
  gtw = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKBHw7xZaSnCPBXCEx5pGUr5PVLg2CcNy3BGN6OYj4qi root@gtw";
  publicKeys = [ zxc gtw ];
in
{
  "xray.age".publicKeys = publicKeys;
  "wireguard.age".publicKeys = publicKeys;
  "cloudflare.age".publicKeys = publicKeys;
}
