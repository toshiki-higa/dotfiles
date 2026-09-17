#!/bin/zsh

set -euo pipefail

# Load Home Manager's newly generated shell environment.
source "$HOME/.zshrc" &>/dev/null || true

pi_packages=(
  "npm:@calesennett/pi-codex-fast"
  "git:github.com/earendil-works/pi-review"
)

print '\n--- Setup AI Tools ---------'
contains_pi_package() {
  local needle="$1"
  shift

  local package
  for package in "$@"; do
    [[ "$package" == "$needle" ]] && return 0
  done
  return 1
}

# Treat pi_packages as the source of truth. Package entries in `pi list` are
# indented by exactly two spaces; their installation paths use four spaces.
installed_pi_packages=()
while IFS= read -r line; do
  if [[ "$line" == "  "* && "$line" != "    "* ]]; then
    installed_pi_packages+=("${line#  }")
  fi
done <<< "$(pi list --no-approve)"

# Install before removing so a failed install does not remove working packages.
for pi_package in "${pi_packages[@]}"; do
  if contains_pi_package "$pi_package" "${installed_pi_packages[@]}"; then
    print -r -- "[SKIP] Pi package already installed: $pi_package"
  else
    print -r -- "[RUN] Install Pi package: $pi_package"
    pi install "$pi_package" --no-approve
    print -r -- "[DONE] Install Pi package: $pi_package"
  fi
done

for installed_pi_package in "${installed_pi_packages[@]}"; do
  if ! contains_pi_package "$installed_pi_package" "${pi_packages[@]}"; then
    print -r -- "[RUN] Remove unmanaged Pi package: $installed_pi_package"
    pi remove "$installed_pi_package" --no-approve
    print -r -- "[DONE] Remove unmanaged Pi package: $installed_pi_package"
  fi
done

herdr_integrations="$(herdr integration status)"
if [[ "$herdr_integrations" != *'pi: current'* ]]; then
  print '[RUN] Install Herdr integration for Pi'
  herdr integration install pi
  print '[DONE] Install Herdr integration for Pi'
else
  print '[SKIP] Herdr integration for Pi is current'
fi

if ! moshi-hook status --json | jq -e '.hooks[] | select(.target == "pi" and .status == "current")' >/dev/null; then
  print '[RUN] Install Moshi hooks for Pi'
  moshi-hook install --target pi
  print '[DONE] Install Moshi hooks for Pi'
else
  print '[SKIP] Moshi hooks for Pi are current'
fi

if herdr status server --json | jq -e '.running == true' >/dev/null; then
  print '[RUN] Reload Herdr configuration'
  herdr server reload-config >/dev/null
  print '[DONE] Reload Herdr configuration'
else
  print '[SKIP] Reload Herdr configuration: server is not running'
fi
