#!/bin/zsh

set -euo pipefail

marker="${TMPDIR:-/tmp}/chezmoi-home-manager-activation-${UID}"
source_dir="${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi/dot_config/home-manager"

print '\n--- Detect Nix changes -----'
print '[RUN] Detect Nix changes'

# Retry a failed action.
action=""
if [[ -f "$marker" ]]; then
  action="$(<"$marker")"
  print -r -- "  pending: $action"
fi

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  print '  nix-darwin: not installed'
  action="initial"
else
  for source_file in "$source_dir"/*.nix(N); do
    filename="${source_file:t}"
    cmp -s "$source_file" "$HOME/.config/home-manager/$filename" && continue

    print -r -- "  changed: $filename"
    if [[ "$filename" == "common.nix" ]]; then
      if [[ -z "$action" ]]; then
        action="update-home-manager"
      fi
    else
      action="update-darwin"
      break
    fi
  done
fi

if [[ -n "$action" ]]; then
  print -r -- "$action" > "$marker"
  print -r -- "[DONE] Detect Nix changes: $action"
else
  print '[DONE] Detect Nix changes'
  print '[SKIP] Nix activation: no changes'
fi
