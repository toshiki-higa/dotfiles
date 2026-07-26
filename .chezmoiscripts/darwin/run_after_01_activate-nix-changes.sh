#!/bin/zsh

set -euo pipefail

marker="${TMPDIR:-/tmp}/chezmoi-home-manager-activation-${UID}"
flake="$HOME/.config/home-manager#macos"

print '\n--- Activate Nix changes ---'
if [[ ! -f "$marker" ]]; then
  print '[SKIP] Nix activation: no action selected'
  exit 0
fi
action="$(<"$marker")"

# Load Nix when it is not in PATH.
if ! command -v nix >/dev/null 2>&1; then
  print '[RUN] Load Nix environment'
  nix_profile="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  if [[ ! -r "$nix_profile" ]]; then
    print -u2 "Nix is not installed or its profile could not be found."
    exit 1
  fi
  source "$nix_profile"
  print '[DONE] Load Nix environment'
fi

case "$action" in
  initial)
    print '[RUN] Initial nix-darwin activation'
    sudo "$(command -v nix)" run nix-darwin -- switch --flake "$flake"
    ;;
  update-darwin)
    print '[RUN] Apply nix-darwin configuration'
    sudo "$(command -v darwin-rebuild)" switch --flake "$flake"
    ;;
  update-home-manager)
    if ! command -v home-manager >/dev/null 2>&1; then
      print -u2 "home-manager command not found. Run the initial nix-darwin activation first."
      exit 1
    fi
    print '[RUN] Apply Home Manager configuration'
    home-manager switch --flake "$flake"
    ;;
  *)
    print -u2 "Unknown action: $action"
    exit 1
    ;;
esac

# Clear after success.
rm -f "$marker"
print -r -- "[DONE] Nix activation: $action"
