HOSTS := gtw a b

switch:
	nix run nixpkgs#deploy-rs -- .

$(addprefix switch-, $(HOSTS)):
	@host=$(@:switch-%=%); \
	nix run nixpkgs#deploy-rs -- .#$$host

update:
	nix flake update --commit-lock-file

reformat:
	nixpkgs-fmt .

dry-build:
	nixos-rebuild dry-build --flake .#gtw

$(addprefix dry-build-, $(HOSTS)):
	@host=$(@:dry-build-%=%); \
	nixos-rebuild dry-build --flake .#$$host
