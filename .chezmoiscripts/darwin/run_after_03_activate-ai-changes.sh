#!/bin/zsh

set -euo pipefail

# Force Home Manager's newly generated session variables to be loaded.
unset __HM_SESS_VARS_SOURCED
source "$HOME/.zshrc" &>/dev/null || true

pi_packages=(
  "npm:@superwhisper/pi"
)

print '\n--- Setup AI Tools ---------'
installed_pi_packages="$(pi list --no-approve)"
for pi_package in "${pi_packages[@]}"; do
  if [[ "$installed_pi_packages" != *"$pi_package"* ]]; then
    print -r -- "[RUN] Install Pi package: $pi_package"
    pi install "$pi_package" --no-approve
    print -r -- "[DONE] Install Pi package: $pi_package"
  else
    print -r -- "[SKIP] Pi package already installed: $pi_package"
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

if herdr status server >/dev/null 2>&1; then
  print '[RUN] Reload Herdr configuration'
  herdr server reload-config >/dev/null
  print '[DONE] Reload Herdr configuration'
else
  print '[SKIP] Reload Herdr configuration: server is not running'
fi
