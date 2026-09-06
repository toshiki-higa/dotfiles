{ config, pkgs, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  inherit (inputs.llm-agents.packages.${system})
    pi
    opencode
    agent-browser
    herdr
    hunk
    ;
  mcpx = inputs.mcpx.packages.${system}.default;
  vscodeGitGutter = "${inputs.shikher-yazi-plugins}/vscode-git-gutter.yazi";
  skillSources = builtins.mapAttrs (_: src:
    src // {
      path = if src.input or null != null
        then inputs.skills.inputs.${src.input}
        else inputs.skills;
      input = null;
    }
  ) inputs.skills.sources;
in

{
  # Do not change this value casually. It controls Home Manager compatibility.
  home.stateVersion = "24.11";

  home.sessionVariables = {
    EDITOR = "hx";
    HOMEBREW_FORBIDDEN_FORMULAE = "node python python3 pip npm pnpm yarn";
    XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
    XDG_CACHE_HOME = "${config.home.homeDirectory}/.cache";
    XDG_DATA_HOME = "${config.home.homeDirectory}/.local/share";
    XDG_STATE_HOME = "${config.home.homeDirectory}/.local/state";
  };
  home.sessionPath = [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${config.home.username}/bin"
    "$HOME/.nix-profile/bin"
    "$HOME/.local/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "$HOME/bin"
    "$HOME/.cargo/bin"
    "$HOME/.moon/bin"
  ];

  programs.home-manager.enable = true;

  # Use Home Manager for packages only (configuration by chezmoi)
  home.packages = with pkgs; [
    # Bootstrap
    chezmoi

    # Git
    git
    gh
    ghq
    git-wt
    lazygit

    # Shell
    starship
    sheldon
    carapace

    # Better Standard Command
    zoxide
    bat
    eza
    ripgrep
    fd
    xh
    fzf

    # File Viewer / Editor
    helix
    jq
    imagemagick
    resvg
    ffmpeg
    poppler
    p7zip

    # Development
    mise
    just
    cloudflared
    mosh
    turso-cli
    sqld

    # AI
    pi
    opencode
    agent-browser
    herdr
    hunk
    mcpx

    # Secret
    bitwarden-cli

    # Other utilities
    rclone
  ];

  programs.yazi = {
    enable = true;
    plugins = with pkgs.yaziPlugins; {
      vscode-git-gutter = vscodeGitGutter;
      git = {
        package = git;
        setup = true;
        settings.order = 1500;
      };
    };
  };

  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv.enable = true;
    enableZshIntegration = false; # managed ~/.zshrc by chezmoi
  };

  programs.nh = {
    enable = true;
    darwinFlake = "${config.home.homeDirectory}/.config/home-manager";
  };

  # Agent Skills
  programs.agent-skills = {
    enable = true;
    sources = skillSources;
    skills.enable = [
      "ai/fetch-url"
      "ai/orchestrate"
      "ai/web-search"
      "tooling/agent-browser"
      "tooling/nix-setup"
    ];
    targets.agents.enable = true;
  };
}
