#!/bin/zsh
# Add repository for Github CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update -y

# Install applications via apt
sudo apt install -y \
    git \
    gh \
    code \
    rpi-connect

# Install mise
curl https://mise.run | sh
mise trust
mise i

# Configure Github CLI
# TODO: set token via bitwarden cli
# echo "" | gh auth login --with-token

# Configure rpi-connect
rpi-connect on

printf '\n\n\e[32mCompleted to setup raspberry pi!\e[0m\n'
printf '\e[33mPlease login to rpi-connect: rpi-connect signin\e[0m\n'
printf '\e[33mPlease login to Github CLI: gh auth login\e[0m\n'
