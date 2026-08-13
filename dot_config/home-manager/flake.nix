{
  description = "toshiki-higa's nix-darwin and Home Manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://yatainc.github.io/mcpx"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "yata-one-mcpx-1:0GPBIC52/PszrTcDzKJIZ7qMmcRvKAWK2WzZYKskgCs="
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

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, llm-agents, mcpx, shikher-yazi-plugins, ... }:
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
        _module.args = {
          apm = llm-agents.packages.${system}.apm;
          pi = llm-agents.packages.${system}.pi;
          opencode = llm-agents.packages.${system}.opencode;
          agent-browser = llm-agents.packages.${system}.agent-browser;
          herdr = llm-agents.packages.${system}.herdr;
          hunk = llm-agents.packages.${system}.hunk;
          mcpx = mcpx.packages.${system}.default;
          vscodeGitGutter = "${shikher-yazi-plugins}/vscode-git-gutter.yazi";
        };
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
