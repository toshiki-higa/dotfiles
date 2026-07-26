#!/bin/zsh

set -euo pipefail

# Load Home Manager's newly generated shell environment.
source "$HOME/.zshrc" &>/dev/null || true

print '\n--- Activate mise changes --'
print '[RUN] Install mise tools'
mise trust "$HOME/.config/mise/config.toml"
mise install
print '[DONE] Install mise tools'
