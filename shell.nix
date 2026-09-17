# Compatibility shim for classic `nix-shell` to use the flake's devShell
(builtins.getFlake (toString ./.)).devShells.${builtins.currentSystem}.default
