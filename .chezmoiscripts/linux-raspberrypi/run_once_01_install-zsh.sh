#!/bin/bash
# Update the system
sudo apt update -y

# Install Zsh if not installed
if test ! $(which zsh); then
  printf '\n\n\e[33mZsh not found. \e[0mInstalling Zsh...'
  sudo apt install -y zsh
else
  printf '\n\n\e[0mZsh found. Continuing...'
fi

if [[ "$SHELL" != *zsh ]]; then
  printf '\n\n\e[33mSwitching to Zsh...\e[0m'
  sudo chsh -s "$(which zsh)" $(whoami)
else
  printf '\n\n\e[0mAlready using Zsh.\e[0m'
fi

printf '\n\n\e[32mCompleted: Default shell = Zsh...\e[0m\n'
