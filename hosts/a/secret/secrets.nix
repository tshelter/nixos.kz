let
  zxc = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx";
  a = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAVqYACMZ8LAPAXJbqGRaRtnF5mSR+KyMVJlInleeHDP root@a";
  publicKeys = [ zxc a ];
in
{
  "xray.age".publicKeys = publicKeys;
  "wireguard.age".publicKeys = publicKeys;
}
