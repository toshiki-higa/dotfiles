# dotfiles

Manage by [chezmoi](https://github.com/twpayne/chezmoi) + [Nix](https://github.com/nixos/nix).

## Prerequirements

- Login to App Store (Only Mac)

## Usage

### Setup

```sh
# 0. Install Nix (Determinate Systems installer recommended).
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 1. Bootstrap chezmoi
nix run nixpkgs#chezmoi -- init --apply toshiki-higa
```

### Update

```sh
# Apply Changes　in dotfiles
just dotfiles-apply # chezmoi apply

# Explicitly update all tools to the latest version
just dotfiles-upgrade
```
