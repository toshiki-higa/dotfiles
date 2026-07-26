#!/bin/sh

set -eu

if [ "$(id -u)" -eq 0 ]; then
  cat >&2 <<'EOF'
Error: chezmoi must not be run as root.

Run without sudo:
  chezmoi apply
  nix run nixpkgs#chezmoi -- init --apply toshiki-higa

The dotfiles scripts invoke sudo internally only where required.
EOF
  exit 1
fi
