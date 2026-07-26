{ config, pkgs, apm, pi, opencode, agent-browser, herdr, hunk, mcpx, ... }:

{
  # Do not change this value casually. It controls Home Manager compatibility.
  home.stateVersion = "24.11";

  home.sessionVariables = {
    EDITOR = "hx";
    HOMEBREW_FORBIDDEN_FORMULAE = "node python python3 pip npm pnpm yarn";
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
