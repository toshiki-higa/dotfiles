{ config, pkgs, apm, pi, opencode, agent-browser, herdr, hunk, mcpx, ... }:

{
  # Do not change this value casually. It controls Home Manager compatibility.
  home.stateVersion = "24.11";
  home.sessionPath = [
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

  # Start with package management only. Shell and application configuration
  # remains owned by chezmoi to avoid managing the same file from two places.
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
    jq
    glow
    delta

    # Development
    mise
    just
    helix
    yazi
    cloudflared
    mosh
    turso-cli

    # AI
    apm
    pi
    opencode
    agent-browser
    herdr
    hunk
    mcpx

    # Secret
    rbw
    pinentry_mac

    # Other utilities
    rclone
    ffmpeg
  ];

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
}
