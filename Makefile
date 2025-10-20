switch:
	nix run nixpkgs#deploy-rs .

update:
	nix flake update --commit-lock-file

reformat:
	nixpkgs-fmt .

dry-build:
	nixos-rebuild dry-build --flake .#gtw
