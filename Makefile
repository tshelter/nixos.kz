switch:
	nixos-rebuild switch --impure --flake .#gtw --target-host root@45.86.80.39 --build-host root@45.86.80.39 --fast

update:
	nix flake update --commit-lock-file

reformat:
	nixpkgs-fmt .

dry-build:
	nixos-rebuild dry-build --impure --flake .#gtw
