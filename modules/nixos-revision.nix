{ self, ... }:
{
  environment.etc."nixos-revision".text = ''
    commit: ${self.rev or self.dirtyRev or "unknown"}
    status: ${if self ? rev then "clean" else "dirty"}
    store: ${self.outPath}
  '';
}
