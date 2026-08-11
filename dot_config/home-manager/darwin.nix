{ pkgs, username, ... }:

{
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
  };

  # Determinate manages the Nix daemon and nix.conf. Let nix-darwin manage
  # the rest of the system without replacing that installation.
  nix.enable = false;

  # Let Determinate Nix keep ownership of /etc/zshrc.
  programs.zsh.enable = false;

  # Allow sudo authentication with Touch ID.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Pin and install Homebrew itself through the flake. autoMigrate adopts the
  # existing official /opt/homebrew installation on the first activation.
  nix-homebrew = {
    enable = true;
    user = username;
    autoMigrate = true;
    enableRosetta = false;
  };

  system = {
    primaryUser = username;
    stateVersion = 6;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        InitialKeyRepeat = 14;
        KeyRepeat = 1;
        ApplePressAndHoldEnabled = false;
      };

      finder = {
        AppleShowAllFiles = true;
        FXEnableExtensionChangeWarning = false;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      dock = {
        autohide = true;
        show-recents = false;
        mru-spaces = false;
        tilesize = 48;
      };

      trackpad.Clicking = true;

      CustomUserPreferences."com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };

  # Clean old profiles and unreachable store paths every Sunday at 03:15.
  # Run as a root daemon so nix-darwin system generations are included.
  launchd.daemons.nh-clean.serviceConfig = {
    ProgramArguments = [
      "${pkgs.nh}/bin/nh"
      "clean"
      "all"
      "--keep-since"
      "30d"
      "--keep-one"
    ];
    StartCalendarInterval = [
      {
        Weekday = 7;
        Hour = 3;
        Minute = 15;
      }
    ];
    StandardOutPath = "/var/log/nh-clean.log";
    StandardErrorPath = "/var/log/nh-clean.error.log";
  };

  # Homebrew is intentionally limited to GUI applications and Mac App Store
  # apps. CLI packages belong to Home Manager, and runtimes/tools to mise.
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = true;
      cleanup = "none";
    };

    # Required for homebrew.masApps (brew bundle does not install mas itself).
    # Custom-tap CLIs that are not practical to manage via nixpkgs.
    # Homebrew 6 requires non-official taps/formulae to be explicitly trusted.
    taps = [
      {
        name = "rjyo/moshi";
        trusted = true;
      }
      {
        name = "nikitabobko/tap";
        trusted = true;
      }
      {
        name = "felixkratz/formulae";
        trusted = true;
      }
    ];
    brews = [
      "mas"
      "moshi-hook"
      "borders"
    ];

    casks = [
      # General utilities
      "arc"
      "readdle-spark"
      "raycast"
      "shottr"
      "thaw"
      "notchnook"
      "aerospace"

      # Input utilities
      "karabiner-elements"
      "azookey"
      "superwhisper"

      # Developer tools
      "zed"
      "ghostty"
      "orbstack"
      "tailscale-app"
      "macfuse"

      # Private
      "altserver"
      "soduto"

      # Work
      "slack"
      "meetingbar"

      # Tools
      "chatgpt"
      "openusage"
      "raspberry-pi-imager"
    ];

    masApps = {
      Bitwarden = 1352778147;
      "Microsoft Word" = 462054704;
      "Microsoft Excel" = 462058435;
      "Microsoft PowerPoint" = 462062816;
    };
  };

  users.users.${username}.home = "/Users/${username}";
}
