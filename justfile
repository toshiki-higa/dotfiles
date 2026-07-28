set shell := ["zsh", "-cu"]

# [dotfiles] apply changes
switch:
    #!/bin/zsh
    set -euo pipefail
    chezmoi apply

# [dotfiles] Explicitly upgrade Homebrew and Nix
update:
    #!/bin/zsh
    set -euo pipefail

    flake="$HOME/.config/home-manager"
    lock="$flake/flake.lock"

    print '\n--- Upgrade system ----------'

    print '[RUN] Sync Home Manager configuration'
    chezmoi apply "$flake"
    print '[DONE] Sync Home Manager configuration'

    print '[RUN] Update Homebrew metadata'
    brew update
    print '[DONE] Update Homebrew metadata'

    print '[RUN] Update Nix flake inputs'
    nix flake update --flake "$flake"
    print '[DONE] Update Nix flake inputs'

    print '[RUN] Activate Nix and Homebrew upgrades'
    sudo darwin-rebuild switch --flake "$flake#macos"
    print '[DONE] Activate Nix and Homebrew upgrades'

    print '[RUN] Save flake.lock to dotfiles'
    chezmoi re-add "$lock"
    print '[DONE] Save flake.lock to dotfiles'
