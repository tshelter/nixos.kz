let
  zxc = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYcdiZTkmjVhqK+IEDv6Q9bSSyc7LkWK3vyfsPkVMen dev@zxc.sx";
  b = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFu96Ua2RjHBP9VvHYRYklUEPMWCWstMlLP3U/SFGSu root@b";
  publicKeys = [ zxc b ];
in
{
  "xray.age".publicKeys = publicKeys;
}
