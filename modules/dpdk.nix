{ pkgs, ... }:
let
  dpdk' = pkgs.dpdk.override { withExamples = [ "all" ]; };
in
{
  environment.systemPackages = [
    dpdk'
    dpdk'.examples
  ];
}
