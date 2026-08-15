{
  description = "toshiki-higa's nix-darwin and Home Manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://yatainc.github.io/mcpx"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "yatainc-mcpx-1:vr17tU1/jIMhXnWkl1kAyc1rBFMlo6T9IPDKHhvwbC0="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    llm-agents.url = "github:numtide/llm-agents.nix";
    mcpx.url = "github:yata-one/mcpx";
    shikher-yazi-plugins = {
      url = "github:ShikherVerma/yazi-plugins";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, nix-homebrew, ... }:
    let
      system = "aarch64-darwin";
      username = "toshiki-higa";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Home Manager is the primary user configuration. Reuse the exact same
      # module from both the standalone and nix-darwin evaluation paths.
      homeUser = {
        imports = [ ./common.nix ];
        _module.args = { inherit inputs; };
        home = {
          inherit username;
          homeDirectory = "/Users/${username}";
        };
      };
    in
    {
      # Primary, standalone Home Manager entry point.
      homeConfigurations.macos = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ homeUser ];
      };

      # Optional system layer. This embeds the same Home Manager module rather
      # than defining a second user configuration.
      darwinConfigurations.macos = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit username; };

        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${username} = homeUser;
            };
          }
        ];
      };
    };
}
