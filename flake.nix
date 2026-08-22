{
  description = "dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs_24
            pkgs.pnpm
          ];
          shellHook = ''
            # Resolve project-local bins/modules for pnpm's global virtual store.
            export PATH="$PWD/node_modules/.bin:$PATH"
            export NODE_PATH="$PWD/node_modules"
            # Install deps only when lockfile is newer than the last install.
            if [ -f pnpm-lock.yaml ] && { [ ! -f node_modules/.pnpm/lock.yaml ] || [ pnpm-lock.yaml -nt node_modules/.pnpm/lock.yaml ]; }; then
              echo "Installing dependencies..."
              pnpm install --frozen-lockfile
            fi
          '';
        };
      }
    );
}
