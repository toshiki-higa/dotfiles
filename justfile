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

    print '[RUN] Update tools by mise'
    mise up
    print '[DONE] Update tools by mise'

    print '\n--- Clean up storage --------'

    print '[RUN] Clean up old nix-darwin generations'
    sudo "$(command -v nh)" clean profile \
      /nix/var/nix/profiles/system \
      --keep 2 \
      --no-gcroots \
      --no-direnv
    print '[DONE] Clean up old nix-darwin generations'

    print '[RUN] Clean up Homebrew cache'
    brew cleanup --prune=all
    print '[DONE] Clean up Homebrew cache'

    print '\n--- Sync dotfiles -----------'

    print '[RUN] Save flake.lock to dotfiles'
    chezmoi re-add "$lock"
    print '[DONE] Save flake.lock to dotfiles'
