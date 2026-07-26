#!/bin/zsh

set -euo pipefail

# .zshrc expects an interactive shell where unset parameters are allowed.
source "$HOME/.zshrc" &>/dev/null || true

print '\n--- Activate mise changes --'
print '[RUN] Install mise tools'
mise trust "$HOME/.config/mise/config.toml"
mise install
print '[DONE] Install mise tools'
