#!/bin/zsh

set -euo pipefail

# Force Home Manager's newly generated session variables to be loaded.
unset __HM_SESS_VARS_SOURCED
source "$HOME/.zshrc" &>/dev/null || true

print '\n--- Activate mise changes --'
print '[RUN] Install mise tools'
mise trust "$HOME/.config/mise/config.toml"
mise install
print '[DONE] Install mise tools'
