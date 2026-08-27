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
        "com.apple.trackpad.scaling" = 3.0; # cursor speed by trackpad = max
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

      CustomUserPreferences = {
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };

        "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
          "28".enabled = false; # Disable Command-Shift-3 (save screenshot to file)
          "29".enabled = false; # Disable Command-Control-Shift-3 (copy screenshot to clipboard)
          "30".enabled = false; # Disable Command-Shift-4 (save selected-area screenshot to file)
          "31".enabled = false; # Disable Command-Control-Shift-4 (copy selected-area screenshot to clipboard)
          "64".enabled = false; # Disable Command-Space (Spotlight search)
          "65".enabled = false; # Disable Option-Command-Space (Finder search window)
        };
      };
    };
  };

  # Disable CursorUIViewService to prevent memory growth
  system.activationScripts.postActivation.text = ''
    /bin/mkdir -p /Library/Preferences/FeatureFlags/Domain
    /usr/bin/defaults write \
      /Library/Preferences/FeatureFlags/Domain/UIKit.plist \
      redesigned_text_cursor -dict-add Enabled -bool NO
  '';

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
      "vibeproxy"
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

  # macOS-only packages via nixpkgs
  environment.systemPackages = with pkgs; [
    mole-cleaner
  ];
}
